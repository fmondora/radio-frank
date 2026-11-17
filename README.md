# radio-frank

RadioBar: radio internet sui Sonos di casa (anche più speaker insieme) e sul Mac, dalla barra dei menu di macOS.
App Swift nativa a file singolo, senza dipendenze: parla con i Sonos via UPnP/SOAP.

- `./build.sh`: compila in `~/bin/radiobar` e lo riavvia.
- Stazioni e speaker: `~/.config/radiobar/config.json` (dal menu: «Modifica stazioni…», poi «Ricarica stazioni»).
- In «SUONA SU» spunti una o più destinazioni, anche «Questo Mac». I Sonos scelti si raggruppano: il primo spuntato guida il gruppo. La scelta resta salvata.
- CLI (solo Sonos): `radiobar [--su Office,Spa] speakers | status | play <stazione> | pause | stop | ungroup` (es. `radiobar play jazz --su Office,Spa`).

Note: sulle radio Sonos la pausa diventa Stop. Solo stream `http://`. Mac e Sonos non sono sincronizzati fra loro (ritardo di qualche secondo). `Info.plist` è incorporato nel binario per permettere gli stream http su AVPlayer.
