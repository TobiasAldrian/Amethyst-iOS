#import "KeyboardInput.h"
#import "../utils.h"
#import "../sdl3_hook.h"
#import <GameController/GameController.h>

#include "../glfw_keycodes.h"

// Minecraft 26.3+ runs on SDL3, and SDL3 reads the hardware keyboard by itself (GCKeyboard).
// Forwarding the same keys from here as well made every key arrive twice: Esc / E opened their
// screen and closed it again right away, backspace deleted two characters, and so on.
// SDL never creates text input by itself here, so characters are still sent from this file.
static BOOL sdlHandlesHardwareKeys(void) {
    if (!AmethystSDL3InputActive()) {
        return NO;
    }
    if (@available(iOS 14.0, *)) {
        return GCKeyboard.coalescedKeyboard != nil;
    }
    return NO;
}

// Key repeat: iPadOS reports a held hardware key only once (no repeated pressesBegan, and SDL3 gets
// no repeats from GCKeyboard either), so holding a key in a text field typed a single letter.
// While a screen is open (mouse not grabbed) a held key now repeats like on desktop: its characters
// are sent again, backspace / delete / arrow keys are sent as repeated key presses.
static const NSTimeInterval kKeyRepeatDelay = 0.4;
static const NSTimeInterval kKeyRepeatInterval = 0.05;
static NSTimer *keyRepeatTimer;
static UIKeyboardHIDUsage keyRepeatUsage;
static int keyRepeatKeycode;
static char keyRepeatMods;
static NSString *keyRepeatChars;

static void stopKeyRepeat(void) {
    [keyRepeatTimer invalidate];
    keyRepeatTimer = nil;
    keyRepeatChars = nil;
}

// the key-up can get lost (app switch, keyboard detached), so also check if the key is really still down
static BOOL keyStillHeld(UIKeyboardHIDUsage usage) {
    if (@available(iOS 14.0, *)) {
        GCKeyboard *keyboard = GCKeyboard.coalescedKeyboard;
        if (keyboard == nil) {
            return NO;
        }
        GCControllerButtonInput *button = [keyboard.keyboardInput buttonForKeyCode:(GCKeyCode)usage];
        return button == nil || button.isPressed;
    }
    return YES;
}

static void keyRepeatTick(void) {
    if (isGrabbing || !keyStillHeld(keyRepeatUsage)) {
        stopKeyRepeat();
        return;
    }
    if (keyRepeatChars.length > 0) {
        for (NSUInteger i = 0; i < keyRepeatChars.length; i++) {
            CallbackBridge_nativeSendCharMods([keyRepeatChars characterAtIndex:i], keyRepeatMods);
        }
    } else {
        // 2 = GLFW_REPEAT (SDL3: key down with the repeat flag). The old GLFW path gets a normal
        // press (1) instead, so its stored key state stays "pressed"
        CallbackBridge_nativeSendKey(keyRepeatKeycode, 0 /* scancode */, AmethystSDL3InputActive() ? 2 : 1, keyRepeatMods);
    }
}

static BOOL isRepeatableEditKey(int keycode) {
    switch (keycode) {
        case GLFW_KEY_BACKSPACE:
        case GLFW_KEY_DELETE:
        case GLFW_KEY_DPAD_LEFT:
        case GLFW_KEY_DPAD_RIGHT:
        case GLFW_KEY_DPAD_UP:
        case GLFW_KEY_DPAD_DOWN:
            return YES;
        default:
            return NO;
    }
}

static void startKeyRepeat(UIKeyboardHIDUsage usage, int keycode, NSString *chars, char mods) {
    stopKeyRepeat();
    keyRepeatUsage = usage;
    keyRepeatKeycode = keycode;
    keyRepeatChars = [chars copy];
    keyRepeatMods = mods;
    keyRepeatTimer = [NSTimer timerWithTimeInterval:kKeyRepeatInterval repeats:YES block:^(NSTimer *timer) {
        keyRepeatTick();
    }];
    keyRepeatTimer.fireDate = [NSDate dateWithTimeIntervalSinceNow:kKeyRepeatDelay];
    [NSRunLoop.mainRunLoop addTimer:keyRepeatTimer forMode:NSRunLoopCommonModes];
}

@implementation KeyboardInput

int keycodeTable[UIKeyboardHIDUsageKeyboardRightGUI+1];

+ (void)initKeycodeTable {
    for (int i = UIKeyboardHIDUsageKeyboardA; i <= UIKeyboardHIDUsageKeyboardZ; i++) {
        keycodeTable[i] = i - UIKeyboardHIDUsageKeyboardA + GLFW_KEY_A;
    }

    // 0-9 keys
    keycodeTable[UIKeyboardHIDUsageKeyboard0] = GLFW_KEY_0;
    for (int i = UIKeyboardHIDUsageKeyboard1; i <= UIKeyboardHIDUsageKeyboard9; i++) {
        keycodeTable[i] = i - UIKeyboardHIDUsageKeyboard1 + GLFW_KEY_1;
    }

    // Arrow keys
    keycodeTable[UIKeyboardHIDUsageKeyboardUpArrow] = GLFW_KEY_DPAD_UP;
    keycodeTable[UIKeyboardHIDUsageKeyboardDownArrow] = GLFW_KEY_DPAD_DOWN;
    keycodeTable[UIKeyboardHIDUsageKeyboardLeftArrow] = GLFW_KEY_DPAD_LEFT;
    keycodeTable[UIKeyboardHIDUsageKeyboardRightArrow] = GLFW_KEY_DPAD_RIGHT;

    keycodeTable[UIKeyboardHIDUsageKeyboardComma] = GLFW_KEY_COMMA;
    keycodeTable[UIKeyboardHIDUsageKeyboardPeriod] = GLFW_KEY_PERIOD;

    // Alt keys
    keycodeTable[UIKeyboardHIDUsageKeyboardLeftAlt] = GLFW_KEY_LEFT_ALT;
    keycodeTable[UIKeyboardHIDUsageKeyboardRightAlt] = GLFW_KEY_RIGHT_ALT;

    // Control keys
    keycodeTable[UIKeyboardHIDUsageKeyboardLeftControl] = GLFW_KEY_LEFT_CONTROL;
    keycodeTable[UIKeyboardHIDUsageKeyboardRightControl] = GLFW_KEY_RIGHT_CONTROL;

    // Shift keys
    keycodeTable[UIKeyboardHIDUsageKeyboardLeftShift] = GLFW_KEY_LEFT_SHIFT;
    keycodeTable[UIKeyboardHIDUsageKeyboardRightShift] = GLFW_KEY_RIGHT_SHIFT;

    // Bracket keys
    keycodeTable[UIKeyboardHIDUsageKeyboardOpenBracket] = GLFW_KEY_LEFT_BRACKET;
    keycodeTable[UIKeyboardHIDUsageKeyboardCloseBracket] = GLFW_KEY_RIGHT_BRACKET;

    // Slash keys
    keycodeTable[UIKeyboardHIDUsageKeyboardSlash] = GLFW_KEY_SLASH;
    keycodeTable[UIKeyboardHIDUsageKeyboardBackslash] = GLFW_KEY_BACKSLASH;

    // Page keys
    keycodeTable[UIKeyboardHIDUsageKeyboardPageUp] = GLFW_KEY_PAGE_UP;
    keycodeTable[UIKeyboardHIDUsageKeyboardPageDown] = GLFW_KEY_PAGE_DOWN;

    // Some other keys
    keycodeTable[UIKeyboardHIDUsageKeyboardHome] = GLFW_KEY_HOME;
    keycodeTable[UIKeyboardHIDUsageKeyboardEscape] = GLFW_KEY_ESCAPE;
    keycodeTable[UIKeyboardHIDUsageKeyboardTab] = GLFW_KEY_TAB;
    keycodeTable[UIKeyboardHIDUsageKeyboardReturnOrEnter] = GLFW_KEY_ENTER;
    keycodeTable[UIKeyboardHIDUsageKeyboardSpacebar] = GLFW_KEY_SPACE;
    keycodeTable[UIKeyboardHIDUsageKeyboardDeleteOrBackspace] = GLFW_KEY_BACKSPACE;
    keycodeTable[UIKeyboardHIDUsageKeyboardDeleteForward] = GLFW_KEY_DELETE;
    keycodeTable[UIKeyboardHIDUsageKeyboardGraveAccentAndTilde] = GLFW_KEY_GRAVE_ACCENT;

    keycodeTable[UIKeyboardHIDUsageKeyboardHyphen] = GLFW_KEY_MINUS;
    keycodeTable[UIKeyboardHIDUsageKeyboardEqualSign] = GLFW_KEY_EQUAL;
    keycodeTable[UIKeyboardHIDUsageKeyboardSemicolon] = GLFW_KEY_SEMICOLON;

    // Lock keys
    keycodeTable[UIKeyboardHIDUsageKeyboardCapsLock] = GLFW_KEY_CAPS_LOCK;
    keycodeTable[UIKeyboardHIDUsageKeypadNumLock] = GLFW_KEY_NUM_LOCK;
    keycodeTable[UIKeyboardHIDUsageKeyboardScrollLock] = GLFW_KEY_SCROLL_LOCK;

    // Numpad keys
    keycodeTable[UIKeyboardHIDUsageKeypadSlash] = GLFW_KEY_NUMPAD_DIVIDE;
    keycodeTable[UIKeyboardHIDUsageKeypadAsterisk] = GLFW_KEY_NUMPAD_MULTIPLY;
    keycodeTable[UIKeyboardHIDUsageKeypadHyphen] = GLFW_KEY_NUMPAD_SUBTRACT;
    keycodeTable[UIKeyboardHIDUsageKeypadPlus] = GLFW_KEY_NUMPAD_ADD;
    keycodeTable[UIKeyboardHIDUsageKeypadEnter] = GLFW_KEY_NUMPAD_ENTER;
    keycodeTable[UIKeyboardHIDUsageKeypadEqualSign] = GLFW_KEY_NUMPAD_EQUAL;
    keycodeTable[UIKeyboardHIDUsageKeypad0] = GLFW_KEY_NUMPAD_0;
    for (int i = UIKeyboardHIDUsageKeypad1; i <= UIKeyboardHIDUsageKeypad9; i++) {
        keycodeTable[i] = i - UIKeyboardHIDUsageKeypad1 + GLFW_KEY_NUMPAD_1;
    }

    // Function keys
    for (int i = UIKeyboardHIDUsageKeyboardF1; i <= UIKeyboardHIDUsageKeyboardF12; i++) {
        keycodeTable[i] = i - UIKeyboardHIDUsageKeyboardF1 + GLFW_KEY_F1;
    }
}

+ (BOOL)sendKeyEvent:(UIKey *)key down:(BOOL)isDown {
    char modifiers = 0;

    // convert UIKey's modifiers to GLFW
    if (key.modifierFlags & UIKeyModifierAlphaShift) {
        modifiers |= GLFW_MOD_CAPS_LOCK;
    }
    if (key.modifierFlags & UIKeyModifierShift) {
        modifiers |= GLFW_MOD_SHIFT;
    }
    if (key.modifierFlags & UIKeyModifierAlternate) {
        modifiers |= GLFW_MOD_ALT;
    }
    if (key.modifierFlags & UIKeyModifierControl) {
        modifiers |= GLFW_MOD_CONTROL;
    }

    // send the keycode (keyCode is checked first, the table only covers the keyboard page)
    UIKeyboardHIDUsage usage = key.keyCode;
    int keycode = (usage >= 0 && usage <= UIKeyboardHIDUsageKeyboardRightGUI) ? keycodeTable[usage] : 0;

    // any new key press ends the current repeat (like on desktop), and so does releasing the held key
    if (isDown || usage == keyRepeatUsage) {
        stopKeyRepeat();
    }

    if (!sdlHandlesHardwareKeys()) {
        if (keycode != 0) {
            CallbackBridge_nativeSendKey(keycode, 0 /* scancode */, isDown, modifiers);
        } else {
            NSLog(@"KeyboardInput: Unhandled key %lu", (unsigned long)key.keyCode);
        }
    }

    // Cmd/Ctrl + key is a shortcut, not text (Cmd+V would paste and type a "v"), same as on desktop
    BOOL isShortcut = (key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierControl)) != 0;

    // key.characters.length < 11: skip sending characters if the string starts with UIKeyInput
    NSMutableString *typed = [NSMutableString string];
    if (isDown && !isShortcut && key.characters.length < 11) {
        for (NSUInteger i = 0; i < key.characters.length; i++) {
            unichar keychar = [key.characters characterAtIndex:i];
            // backspace, enter, tab, esc, delete and Apple's function-key characters are keys, not text
            if (keychar < 0x20 || keychar == 0x7F || (keychar >= 0xF700 && keychar <= 0xF8FF)) {
                continue;
            }
            // Send each character only once: nativeSendCharMods already falls back to the char
            // callback (GLFW) and forwards to SDL3 (26.3+). Also calling nativeSendChar typed every
            // character twice.
            CallbackBridge_nativeSendCharMods(keychar, modifiers);
            [typed appendString:[NSString stringWithCharacters:&keychar length:1]];
        }
    }

    // keep repeating while the key is held, only in screens (chat, signs, ...), never in-game
    if (isDown && !isShortcut && !isGrabbing && (typed.length > 0 || isRepeatableEditKey(keycode))) {
        startKeyRepeat(usage, keycode, typed, modifiers);
    }

    return keycode != 0 || isDown;
}

@end
