# Docker Deployment Setup

## Übersicht

Dieses Repository enthält die Docker-Konfiguration für HAWKI als eigenständiges Modul, das als Submodule/Subfolder in das HAWKI-Hauptprojekt eingebunden werden kann.

## Struktur

```
HAWKI/                          # Hauptprojekt-Root
├── _docker/                    # Dieses Repository (als Submodule)
│   ├── dockerfile/
│   │   ├── Dockerfile          # Multi-stage Build-Konfiguration
│   │   └── DOCKER.md           # Docker-Dokumentation
│   ├── deploy-dev.sh
│   ├── deploy-staging.sh
│   ├── deploy-prod.sh
│   └── ...
├── Dockerfile                  # ← Wird automatisch hierher kopiert
└── DOCKER.md                   # ← Wird automatisch hierher kopiert (optional)
```

## Automatische Datei-Kopie

Die Deployment-Skripte kopieren beim **ersten Ausführen** automatisch die notwendigen Dateien aus `dockerfile/` ins Projekt-Root:

- ✅ `Dockerfile` → `../Dockerfile`
- ✅ `DOCKER.md` → `../DOCKER.md` (falls vorhanden)

### Warum?

Docker benötigt das `Dockerfile` im Build-Context-Root (neben dem Code), da es auf das gesamte Projekt zugreifen muss. Das Submodule kann aber nicht direkt im Root platziert werden.

## Verwendung als Submodule

### Integration ins HAWKI-Projekt

```bash
# Im HAWKI-Hauptprojekt
git submodule add <repo-url> _docker
git submodule update --init --recursive
```

### .gitignore im Hauptprojekt

Fügen Sie folgende Zeilen zur `.gitignore` des Hauptprojekts hinzu:

```gitignore
# Docker files (managed by _docker submodule)
/Dockerfile
/DOCKER.md
```

Diese Dateien werden beim Deployment automatisch aus dem Submodule kopiert und sollten nicht im Hauptprojekt versioniert werden.

## Deployment

### Development

```bash
cd _docker
./deploy-dev.sh --build
```

Beim ersten Ausführen:
1. ✅ Kopiert `Dockerfile` ins Projekt-Root
2. ✅ Initialisiert Environment (`.env`)
3. ✅ Baut Docker Images
4. ✅ Startet Container

### Staging

```bash
cd _docker
./deploy-staging.sh --build
```

### Production

```bash
cd _docker
./deploy-prod.sh
```

## Updates

### Submodule aktualisieren

```bash
# Im Hauptprojekt
cd _docker
git pull origin main

# Falls Dockerfile geändert wurde
rm ../Dockerfile ../DOCKER.md
cd _docker
./deploy-staging.sh --build  # Kopiert und baut neu
```

### Code-Updates (Development)

```bash
git pull
cd _docker
./update-dev.sh
```

## Änderungen am Dockerfile

Änderungen am `Dockerfile` sollten **nur im `_docker` Submodule** vorgenommen werden:

1. Änderungen in `_docker/dockerfile/Dockerfile` vornehmen
2. Commiten und pushen im Submodule
3. Im Hauptprojekt: Submodule aktualisieren
4. Deployment-Skript erneut ausführen (kopiert aktualisierte Version)

```bash
# Im _docker Submodule
cd _docker
git add dockerfile/Dockerfile
git commit -m "Update Dockerfile"
git push

# Im Hauptprojekt
cd ..
git add _docker
git commit -m "Update docker submodule"
git push
```

## Troubleshooting

### Dockerfile nicht gefunden

```
❌ Error: dockerfile/Dockerfile not found in _docker directory!
```

**Lösung:** Stellen Sie sicher, dass Sie im `_docker` Verzeichnis sind und `dockerfile/Dockerfile` existiert.

### Veraltetes Dockerfile im Root

Falls das Dockerfile im Root veraltet ist:

```bash
# Aus Hauptprojekt-Root
rm Dockerfile DOCKER.md
cd _docker
git pull
./deploy-staging.sh --build  # Kopiert aktuelle Version
```

### Manuelle Kopie erzwingen

```bash
cd _docker
cp dockerfile/Dockerfile ../Dockerfile
cp dockerfile/DOCKER.md ../DOCKER.md
```

## Vorteile dieser Struktur

✅ **Getrennte Wartung**: Docker-Konfiguration kann unabhängig aktualisiert werden  
✅ **Wiederverwendbar**: Gleiche Docker-Config für mehrere Projekte  
✅ **Automatisch**: Keine manuellen Kopierschritte nötig  
✅ **Versionskontrolle**: Änderungen werden im Submodule getrackt  
✅ **Kompatibel**: Docker Build-Context bleibt im Projekt-Root  
