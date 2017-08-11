# Logistic Wagon

I got so tired of trying to find a way to keep my outposts stocked! This is my solution. It adds a new cargo wagon that acts like a magical logistic chest. It will seem complicated at first, but once you "get it", it makes sense :-)
Please note when you read step 1 and 2 that stack sizes are configurable per station/wagon.

## Step 1: Train with Logistic Wagon stops at a station in automatic mode

Each Logistic Wagon looks to its immediate 4 spots for a logistic chest of either type. If it finds none, it acts like a normal wagon. If it finds 1 or more chests, it acts on each chest individually in random order.

It can act on the same chest type more than once at the same stop.

### 1.1 Storage (yellow)
Dumps as much as possible of the wagons non-filtered inventory into it.

### 1.2 Passive Provider (red)
If the wagon is filtered, inserts enough items into the chest so that it has one full stack of each filtered item.

### 1.3 Active Provider (purple)
Does one of 2 things, either;

1. If the chest is completely blocked by a red bar, it dumps all non-filtered contents from the wagon into the chest (treats it like a yellow chest) and then reapplies the full red bar, or
2. If the chest is not red-barred, and the wagon is filtered, it inserts as many items as the logistic network the chest belongs to are missing in order to reach one stack of each filtered item (so if the logistic network contains 60 ammunition clips, it will insert 40).

### 1.4 Requester (blue)
Does one of 2 things, either;

1. If the blue chest is completely blocked by a red bar, it removes the red bar so that the chest can be filled up by whatever system is in place (inserter or bot puts empty barrels for example - for dumping into the wagon back to base), or
2. If the wagon is filtered, and the chest has any item request that is set to zero (any item, like empty barrel), it will request enough items to the chest to fill all filtered slots in the wagon (fill up with ammo and stuff at the base). It will only be able to request 9 different item types and will leave the zero-request-slot alone. It will only request enough items to fill up its filtered slots. It will not request items that are set as a zero-request in the chest even if they are filtered in the wagon inventory.

## Step 2: The train leaves the station

### 2.1 Storage (yellow)
Ignored.

### 2.2 Passive Provider (red)
All contents of all passive provider chests are fully loaded into the wagon, until the wagon is full. Ignores all filters, simply grabs everything.

### 2.3 Active Provider (purple)
Ignored.

### 2.4 Requester chests (blue)
Does one of two things, either:

1. If the chest has a request for an item set to zero, takes enough items from that chest to fill (depending on configured stack sizes, like always) the wagons filtered slots (and nothing else), then removes all non-zero requests from the chest, or
2. If there is a request for items higher than zero set, it will grab everything (not just requested items) from that chest (for example all empty barrels, alien artifacts, or ore), then applies a full red bar to the chest inventory.

# Stack size configuration
Multiple wagons connected to the same train act independently on their chests, and can have different stack size configurations.

If a Logistic Wagon finds a constant combinator with any parameter (it ignores empty ones) set in one of the 4 chest spots, it uses the parameters in that CC for determining stack sizes of each item type it handles during that stop, if they are set.

The combinators do not have to be connected to anything.

The addon comes with a few preconfigured stack sizes at the top of control.lua, explicitly overriding the game data on these items. Currently, they are:

> ["gun-turret"] = 5
> ["laser-turret"] = 5
> ["flamethrower-turret"] = 5
> ["logistic-robot"] = 5
> ["construction-robot"] = 5
> ["repair-pack"] = 15

If you want to load up your wagons with 50 gun turrets (per filtered slot), you need to put down a CC and override this.
In prioritized order, the wagons determine/read stack sizes from: (1) attached constant combinator, (2) control.lua, (3) game defaults.

If you configure stack size overrides, they must be set per-wagon, per-station.
_So, hopefully to make that clear; the combinator configurations are not saved for other stops in the schedule, or for other wagons in the same train. They are independent per station and wagon._ So if you at the depot set up a gun-turret stack size of 50, it will still use 5 as the stack size when it reaches the other stations in its schedule. Unless you override it there as well.

# How-to Guides

## How to: Stock outposts with X/Y/Z

1. In your base, make a station and put a requester chest immediately next to the middle of the Logistic Wagon (take a look at the green squares in the screenshot above). Set one of the 10 request slots in the chest to Empty Barrel with a value of 0. You need to type "0" in manually, because the slider only goes down to 1. If you filter other slots in the wagon for items that you dont actually want to fill it with, set those to zero as well.
2. In the Logistic Wagon, filter slots for ammunition, repair packs, full barrels, empty barrels, gun turrets, flamethrower turrets, laser turrets, logistic robot, and construction robot. That's 9, and max types for 1 wagon. Or whatever other items you want to provide for your outpost. You can also hook up more than one wagon (so 9 more types in that one), of course.
3. Send the wagon in automatic mode to the station you made, and set it to wait for 120 seconds or however long you think it will take your bots to fill the chest (remember the requests are set when the train arrives, so it depends how far the bots have to travel, etc).
4. At your outpost, put down an active provider chest (immediately next to the middle section of where the wagon will be) and make sure it's inside the grid of a roboport with 1 logistic bot, or whatever you want.
5. Send the train to the outpost in automatic mode and set it to wait there for however long you want. Immediately when it arrives, it will read the contents of the logistic network of the active provider chest and dump a stacks worth of all the filtered items in the wagon into the active provider chest.

## How to: Remove items from outposts (empty barrels, excess alien artifacts, etc)

1. At the outpost, put down an active requester (blue) chest in one of the 4 spots that connect to the Logistic Wagon (look at the screenshots above). Set requests in the chest for items you want to dump (10x Empty Barrel, 500x Alien Artifact, etc)
2. Fill the requester chest inventory with the red bar completely (click the X in the inventory and drag it to fill the entire inventory). When the train arrives, it will remove the red bar, and reapply it again when it leaves.
3. At the home base, set a filter inserter to unload per item type into whatever you want and set the filters appropriately.

## How to: Use the Logistic Wagon as a normal wagon with a few filtered slots

The Logistic Wagon has 48 slots, compared to the 40 slots in the normal cargo wagon.

1. At your depot or unloader station, put down one request chest with a zero-item request in a spot like on the screenshots. Either use filtered inserters to unload the wagon or put down a storage (yellow) chest. Inserters are faster because you have 11 spots remaining for inserters on the wagon but on the storage chest there are only 3.
2. Filter a few slots in the Logistic Wagon for whatever items you want to bring out to the outpost.
3. At the outpost, either put down an active provider chest, or a passive provider chest, depending on what you want to happen, in one of the 4 positions, and use inserters to fill the rest of the wagon with ore. Or passive provider chests (which the wagon will grab when it leaves), but then you can only have 3-4 of them as buffers to load from as opposed to 11 with inserters.

## How to: Clean the wagons inventory at the depot

1. Put down an active provider (purple) chest and fully apply a red bar to it.
2. When the wagon arrives, it will remove the red bar, dump all non-filtered wagon contents into it, and reapply the red bar.
You can also use storage chests, but the problem with these is that bots will load stuff into them so it might not be empty when the train wants to dump contents.

# Changelog
- 0.2.4: Fixed events for 0.15.10.
- 0.2.2: Dont ignore passive provider chests even when wagon inventory is empty
- 0.2.1: No longer looks for chests when the train stops at a signal; only at stations.
         You can now put down a constant combinator at any of the 4 spots to override
         the stack sizes completely per-wagon, per-station.
- 0.1.9: Passive Provider chests are now actually handled like described above, previously they were not grabbed when the train started moving unless it had inserted anything into them when it stopped.
- 0.1.8: Forgot to remove a debug message in 0.1.7.
         Changed requirements for the tech and recipe slightly.
- 0.1.7: Prevent on_tick processing for requester chests we did not touch
- 0.1.6: Active Provider (purple) chests with a full red bar are now treated as storage (yellow) chests; the wagon will dump all its non-filtered items into it and reapply the red bar
- 0.1.5: Use the config-adjusted stacksizes whenever anything is filtered. Also had to reset the stored data, so when you load a savegame the wagons wont react to the chests until the next visit to the station.
- 0.1.4: Fixed processing of wagons between save/load cycles
- 0.1.3: Only non-filtered items are dumped into storage (yellow) chests
- 0.1.2: Fixed nil reference bug
- 0.1.1: Initial release
