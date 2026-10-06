## Installation

Buy Dome Keeper on [Steam](https://store.steampowered.com/app/1637320/Dome_Keeper/) (the Linux build, the Windows pck also works). In Steam choose Manage, then Browse local files, and copy `domekeeper.pck` into `ports/domekeeper/`.

The first start prepares the game for your device from your own pck. It takes a few minutes and needs about 350 MB of free space. Press A to begin, and A again when it finishes. It runs again by itself if the pck changes.

## Controls

Buttons are named as the game's prompts show them. On Knulli they act as labelled on the device. Other firmwares use SDL's layout by position, where A is the bottom button (labelled B on Anbernic devices).

| Button | Action |
|--|--|
| Left stick | Move |
| A / B | Pick up, confirm / drop, back |
| X / Y | Gadget 1 / Gadget 2 |
| L1 / R1 | Pick up / drop, menu tabs |
| R2 / L2 | Dome weapon / special ability |
| Start | Menu |
| Select + Start | Quit |

## Notes

* Online services are not available. Single player is tested.
* Set `DK_UI_SCALE` (for example `export DK_UI_SCALE=1.25`) at the top of `Dome Keeper.sh` to change the UI scale.
* No game files are included. All patches are made on your device.

## Reporting problems

Please send `ports/domekeeper/log.txt` and `ports/domekeeper/setup_log.txt`. `log.txt` is rewritten on every start and the run before it is kept as `log.prev.txt` (the setup log likewise), so send both if the game was started again after the problem. Lines starting with `PORT:` list the device, firmware, screen, memory and swap, the state of the setup, and at the end how long the game ran and whether the system ran out of memory.

## Thanks

Bippinbits for the game, the Godot Engine developers, Knifethrower for the PM Porting Tools, and the PortMaster team.
