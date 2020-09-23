# Sync Stick

Copies files of a local folder to a MP3 stick in order.

Many MP3 sticks will play files in order that they have been copied. So
when anything within a folder changes, all contents of that folder have
to be copied again. This script will use internal backup and restore to
avoid copying, which is slow.

### Usage
```
./sync_stick.rb <source folder> [<destination folder>]
```

### Example
```
./sync_stick.rb ~/Stick/ /Volumes/STICK
```
