# Stims

Stim injectors for HELLDIVERS. Each Helldiver carries up to three stims by default (one to four with the Maximum stim count option) and starts every drop and respawn with a full set. An ammo box gives two more, and can be picked up for stims alone when every weapon is full.

A stim takes the key (V by default): the Helldiver raises the left fist and stabs the injector into the neck, standing, moving or prone. Unless a dive, a knockdown, a reload, a throw or a melee cuts the motion short, the stim gives four seconds of endless stamina and 60 health a second, up to full health. The Helldiver moves at aiming speed while the injection plays, the screen edges glow light blue while the stim lasts, and another stim can start three seconds after the last one took effect. With none left, "Out of stims!" shows over the Helldiver.

A downed Helldiver can use a stim to get back up and heal, unless the Allow downed stim option is off.

Passive health regeneration is off: health comes back through stims and other healing. The Preserve passive healing option keeps it.

The loadout card shows a syringe right of the weapon, one charge per stim, spent from the needle down. Other players see the motion and the count of each Helldiver.

## Requirements

- Obsidian API 1.57.0 or later.
- Every player in the lobby runs the mod, at the same version and option values.

## Options

| Option | Default | What it does |
|---|---|---|
| Maximum stim count | 3 | Stims each Helldiver carries, and starts each drop and respawn with (1 to 4). |
| Preserve passive healing | Off | Keeps the slow health regeneration of the game. |
| Allow downed stim | On | A downed Helldiver can use a stim to get back up and heal. |
| Stim sound volume | 0.7 | How loud the stim sound plays. Other players' stims nearby play quieter. |
| Use a stim (key) | V | The key that uses a stim. |

## Notes

- The stim sound plays through Windows, outside the game's own volume settings.
- Other players see a stim about a second after it happens.
