<img width="1339" height="744" alt="image" src="https://github.com/user-attachments/assets/635093e8-4177-4db3-b5f0-49ec4981f519" />

<h1 align="center">Catalog Loader V2</h1>

<p align="center"><b>Browse the Roblox Marketplace and dress your NPCs without leaving Roblox Studio.</b><br>Created by Elaine</p>

---

Catalog Loader V2 is a Roblox Studio plugin for building and dressing NPCs. You can browse the Marketplace with all of its filters, or paste an item ID. The item is imported straight onto the NPCs you have selected. You can spawn ready-made Female or Male rigs, save your finished NPCs into folders that work in every place, and repair NPCs whose body parts or accessories have moved. You can also give the window your own look with seven built-in themes or custom ones.

## Features

### Marketplace browser
- Browse Marketplace accessories, clothing, bundles and more in a grid with thumbnails.
- Use every Marketplace filter: category, creator, price range, sort (Relevance, Most Favorited, Bestselling, Recently Published, price), time period and sales type.
- Classic clothing is included: T-Shirts, Shirts and Pants.
- Imports start only on a **left-click**, so right-clicking an item never imports it by accident.

### Import by ID
- Paste an item ID or a Marketplace link into the box at the bottom and click **Import**.
- **Auto-attach:** with one or more NPCs selected, the item is put on all of them at once. With nothing selected, it is placed in the Workspace.

### Spawn NPC
- **Female / Male switch** above the Spawn NPC button. Female (pink highlight) is selected by default; Male (blue highlight) is on the right.
- Both template rigs are **built into the plugin**, so Spawn NPC works in any place or game, with nothing to set up.
- If a place has its own `Template` (Female) or `Template2` (Male) rig, that one is used instead.
- New NPCs spawn in front of the camera, without stray `Weld` joints. You can turn the **NPC Label** on or off.

### Fix NPC
- Puts body parts and accessories back exactly where they were: the same position, size and angle.
- Works with R6 and R15 rigs, rebuilds missing joints, and replaces missing R6 limbs.

### Folders panel
- Save NPCs and use them again in **any place**, since they are stored with the plugin rather than in the game.
- Organize them in folders. You can rename, recolor and drag to reorder both folders and NPCs.
- See a spinning 3D preview of the selected NPC.
- Each saved NPC shows the date and time it was saved.
- Search NPC and folder names. Folders with a match open automatically.
- Double-click an NPC or folder for **Spawn, Update from Selection, Rename, Change Color, Reset Color and Delete**.

### Themes and window
- Seven built-in themes: **Classic, Sakura Pink, Ocean Blue, Royal Purple, Mint Garden, Sunset** and **Cherry Blossom** (with falling-petal animations).
- Make as many **custom themes** as you like with a color wheel, and edit, rename or delete them whenever you want.
- A **UI transparency** slider, capped so the window never disappears completely.
- The window can be moved, resized and minimized. Closing it resets it to the default size.

## Installing in Roblox Studio

### Option 1: From the Creator Store
1. Open the plugin's Creator Store page *(link coming soon)* and click **Get Plugin**.
2. In Roblox Studio, open the **Plugins** tab (or **Toolbox › Inventory › My Plugins**) and make sure **Catalog Loader V2** is installed and enabled.

### Option 2: Manual install from GitHub
1. Download **`CatalogLoader.lua`** from this repository: open the file and click **Download raw file**.
2. In Roblox Studio, go to the **Plugins** tab and click **Plugins Folder**. This opens your local plugins folder:
   - **Windows:** `%LOCALAPPDATA%\Roblox\Plugins`
   - **macOS:** `~/Documents/Roblox/Plugins`
3. Move `CatalogLoader.lua` into that folder.
4. **Restart Roblox Studio.** Studio loads local plugins only when it starts.

> Install the plugin only once. If you have both the Creator Store version and the local file, delete one of them, or the two copies will compete for the same window.

### Opening the plugin
1. Open any place in Studio.
2. Go to the **Plugins** tab and click **Catalog Loader V2** (the diamond icon with the pink plus).
3. If Studio asks for permissions, allow them. The plugin needs them to load Marketplace items into your place.

## Quick start
1. Pick **Female** or **Male** and click **Spawn NPC**.
2. Keep the new NPC selected, then click any item in the Marketplace grid. It's put on the NPC.
3. Is an accessory out of place, or did a limb get moved? Select the NPC and click **Fix NPC**.
4. Click **Folders** and then **Save NPC** to keep the NPC for use in other places.
5. Click the **gear** to change the theme, adjust transparency or turn the NPC Label on or off.

## Notes
- Your saved NPCs, folders, themes and remembered poses are stored in your own Studio settings on your computer. Other people who install the plugin don't see them.
- Some Marketplace items can't be inserted into places, for example certain limited or off-sale items. When that happens, the plugin shows a message in the status line.
