Copie de https://github.com/ungive/mediaremote-adapter (licence BSD-3, voir LICENSE),
commit indiqué dans VERSION. Compilé par scripts/build-app.sh (sans cmake).

Sert à lire la lecture en cours : depuis macOS 15.4, seul un binaire Apple peut utiliser
MediaRemote, donc le framework est chargé dans /usr/bin/perl via bin/mediaremote-adapter.pl.
