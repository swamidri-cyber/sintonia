#!/usr/bin/env python3
"""SINTONÍA — el joystick, en Linux y en Windows (SDL2).

Escribe por stdout una línea por acción, igual que pad.py del rice:

   nav up|down|left|right     (cruceta o stick izquierdo, con autorrepetición)
   press a|b|x|y|lb|rb|lt|rt|view|menu|guide|ls|rs
   pad connected <nombre> / pad disconnected

SDL conoce casi todos los controles (Xbox, PlayStation, Switch, genéricos) y
los acomoda al formato Xbox. Si SDL no está (Linux), usa pad.py.
"""
import os
import sys
import time
import warnings

warnings.filterwarnings("ignore")            # ("Using SDL2 binaries from pysdl2-dll…")

try:
    import sdl2
except Exception:                      # sin SDL: el lector de Linux de siempre
    if sys.platform.startswith("linux"):
        here = os.path.dirname(os.path.abspath(__file__))
        sys.argv = [os.path.join(here, "pad.py")]
        exec(compile(open(sys.argv[0]).read(), sys.argv[0], "exec"))
    sys.exit(0)

REPEAT_DELAY, REPEAT_EVERY = 0.38, 0.11
DEAD = 16000
TRIGGER = 20000

BOTONES = {
    sdl2.SDL_CONTROLLER_BUTTON_A: "a", sdl2.SDL_CONTROLLER_BUTTON_B: "b",
    sdl2.SDL_CONTROLLER_BUTTON_X: "x", sdl2.SDL_CONTROLLER_BUTTON_Y: "y",
    sdl2.SDL_CONTROLLER_BUTTON_LEFTSHOULDER: "lb", sdl2.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: "rb",
    sdl2.SDL_CONTROLLER_BUTTON_BACK: "view", sdl2.SDL_CONTROLLER_BUTTON_START: "menu",
    sdl2.SDL_CONTROLLER_BUTTON_GUIDE: "guide", sdl2.SDL_CONTROLLER_BUTTON_LEFTSTICK: "ls",
    sdl2.SDL_CONTROLLER_BUTTON_RIGHTSTICK: "rs",
}
CRUZ = {sdl2.SDL_CONTROLLER_BUTTON_DPAD_UP: "up", sdl2.SDL_CONTROLLER_BUTTON_DPAD_DOWN: "down",
        sdl2.SDL_CONTROLLER_BUTTON_DPAD_LEFT: "left", sdl2.SDL_CONTROLLER_BUTTON_DPAD_RIGHT: "right"}


def out(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def main():
    # que lleguen los botones aunque la ventana activa sea otra (la app no es de SDL)
    sdl2.SDL_SetHint(sdl2.SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, b"1")
    sdl2.SDL_SetHint(sdl2.SDL_HINT_NO_SIGNAL_HANDLERS, b"1")      # que la app lo pueda cerrar
    sdl2.SDL_SetHint(b"SDL_JOYSTICK_HIDAPI_PS4_RUMBLE", b"0")
    if sdl2.SDL_Init(sdl2.SDL_INIT_GAMECONTROLLER | sdl2.SDL_INIT_EVENTS) != 0:
        sys.stderr.write("SDL: " + sdl2.SDL_GetError().decode() + "\n")
        return
    abiertos = {}                    # instance id → controlador
    held = None                      # dirección que se mantiene: (dir, origen)
    next_rep = 0.0
    stick = {"x": 0, "y": 0}
    trig = {"lt": False, "rt": False}
    ev = sdl2.SDL_Event()

    def nombre(c):
        n = sdl2.SDL_GameControllerName(c)
        return n.decode("utf-8", "replace") if n else "Control"

    def empezar(d, origen):
        nonlocal held, next_rep
        held = (d, origen)
        next_rep = time.time() + REPEAT_DELAY
        out("nav " + d)

    while True:
        while sdl2.SDL_WaitEventTimeout(ev, 30):
            t = ev.type
            if t == sdl2.SDL_QUIT:
                return
            if t == sdl2.SDL_CONTROLLERDEVICEADDED:
                c = sdl2.SDL_GameControllerOpen(ev.cdevice.which)
                if c:
                    jid = sdl2.SDL_JoystickInstanceID(sdl2.SDL_GameControllerGetJoystick(c))
                    abiertos[jid] = c
                    out("pad connected " + nombre(c))
            elif t == sdl2.SDL_CONTROLLERDEVICEREMOVED:
                c = abiertos.pop(ev.cdevice.which, None)
                if c:
                    sdl2.SDL_GameControllerClose(c)
                if not abiertos:
                    out("pad disconnected")
                    held = None
            elif t == sdl2.SDL_CONTROLLERBUTTONDOWN:
                b = ev.cbutton.button
                if b in CRUZ:
                    empezar(CRUZ[b], "cruz")
                elif b in BOTONES:
                    out("press " + BOTONES[b])
            elif t == sdl2.SDL_CONTROLLERBUTTONUP:
                if ev.cbutton.button in CRUZ and held and held[1] == "cruz" and held[0] == CRUZ[ev.cbutton.button]:
                    held = None
            elif t == sdl2.SDL_CONTROLLERAXISMOTION:
                a, v = ev.caxis.axis, ev.caxis.value
                if a == sdl2.SDL_CONTROLLER_AXIS_LEFTX:
                    stick["x"] = v
                elif a == sdl2.SDL_CONTROLLER_AXIS_LEFTY:
                    stick["y"] = v
                elif a in (sdl2.SDL_CONTROLLER_AXIS_TRIGGERLEFT, sdl2.SDL_CONTROLLER_AXIS_TRIGGERRIGHT):
                    k = "lt" if a == sdl2.SDL_CONTROLLER_AXIS_TRIGGERLEFT else "rt"
                    on = v > TRIGGER
                    if on and not trig[k]:
                        out("press " + k)
                    trig[k] = on
                    continue
                else:
                    continue
                x, y = stick["x"], stick["y"]
                d = None
                if abs(x) > DEAD or abs(y) > DEAD:
                    d = ("right" if x > 0 else "left") if abs(x) > abs(y) else ("down" if y > 0 else "up")
                if d is None:
                    if held and held[1] == "stick":
                        held = None
                elif not held or held[0] != d:
                    empezar(d, "stick")
        if held and time.time() >= next_rep:
            next_rep = time.time() + REPEAT_EVERY
            out("nav " + held[0])


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
