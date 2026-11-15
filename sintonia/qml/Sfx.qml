// Sonidos propios de la app (sintonia/sfx). Volumen y encendido en
// <config>/sonido.json ({ "enabled": true, "sfx": 0.6 }).
import QtQuick
import Sintonia
import QtMultimedia
import Quickshell
import Quickshell.Io

Item {
    id: sfx
    property var names: []
    readonly property string dir: App.dataDir
    property var cfg: ({ enabled: true, sfx: 0.6 })
    property var fx: ({})
    FileView {
        path: App.configDir + "/sonido.json"
        watchChanges: true
        onFileChanged: reload()
        printErrors: false
        onLoaded: { try { sfx.cfg = Object.assign({ enabled: true, sfx: 0.6 }, JSON.parse(text())); } catch (e) {} }
    }
    Instantiator {
        model: sfx.names
        delegate: SoundEffect {
            required property string modelData
            source: App.url("sfx/" + modelData + ".wav")
            volume: sfx.cfg.sfx
            Component.onCompleted: { const m = sfx.fx; m[modelData] = this; sfx.fx = m; }
        }
    }
    function play(name) { if (cfg.enabled && fx[name]) fx[name].play(); }
}
