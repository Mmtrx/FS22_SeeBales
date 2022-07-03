--=======================================================================================================
-- BALESEE SCRIPT
--
-- Purpose:		Allows bales and pallets to show up on the PDA map as hotspots.
-- Author:		Mmtrx		
-- Changelog:
--  v1.0		03.01.2019	original FS17 version by akuenzi (akuenzi@gmail.com)
--	v1.1.0		28.08.2019	updates for FS19, added user interface  
--  v1.1.1		17.09.2019  added pallette support.
--  v1.1.2		08.10.2019	save statistics / add legend in debug mode 
--  v2.0.0.0	19.02.2020  add Gui (settings and statistics)
--  v2.0.0.1	19.06.2020  handle all pallet types, (e.g. straw harvest)
--  v2.1.0.0	30.06.2021  MULTIPLAYER! / handle all bale types, (e.g. Maizeplus forage extension)
--  v3.0.0.0	30.04.2022  port to FS22
--  v3.0.0.1	15.06.2022  bale / pallet detection moved to update(dt). Inspired by GtX EDC
--=======================================================================================================

function debugPrint(text, ...)
	if BaleSee.debug then
		Logging.info(text,...)
	end
end
source(Utils.getFilename("RoyalMod.lua", g_currentModDirectory.."scripts/")) 	-- RoyalMod support functions

BaleSee	= RoyalMod.new(false, true) 	-- (debug, mpSync)
BS = {
	OFF = 1,
	ICON = 2,
	DOT = 3,
	BALES = 	"data/objects/buyableBales/store_buyableBales_",
	BAGS =		"data/objects/bigBagPallet/",
	BIGBAGS =	"data/objects/bigBag/",
	PALLETS =	"data/objects/pallets/",
	PAL_SUPPLIES= 1,
	PAL_FARM 	= 2,
	PAL_FOOD 	= 3,
	PAL_INDUSTRY= 4,
}
function registerAction(player)
		g_inputBinding:beginActionEventsModification(Player.INPUT_CONTEXT_NAME)
		BaleSee:registerActionEventsPlayer(player, g_inputBinding)
		g_inputBinding:endActionEventsModification()
end
function removeAction(player)
		g_inputBinding:beginActionEventsModification(Player.INPUT_CONTEXT_NAME)
		BaleSee:removeActionEventsPlayer(player, g_inputBinding)
		g_inputBinding:endActionEventsModification()
end
function BaleSee:initialize()
	debugPrint("[%s] initialize(): %s", self.name, self.initialized)
	if self.initialized ~= nil then return end -- run only once
	self.bales 		= {} 			-- bale counts per farm and type
	self.pallets 	= {} 			-- pallet counts per farm and type
	self.bHotspots 	= {{},{},{},{},{},{},{},{}}	-- bale hotspots for each farm
	self.pHotspots	= {}			-- all pallet hotspots, each entry is a tuple {hotspot, color, image}
	self.baleToHotspot  = {}		-- index: bale object	
	self.pallToHotspot  = {}		-- index: pallet (vehicle) object	
	self.pal 		= {} 			-- specialization for pallet vehicletype
	self.legend 	= {} 			-- save hotspots for map legend
	self.initialized 	= false
	self.oGui			= nil 		-- object handle Gui controller
	
	---------------- constants -----------------------------------------------------------------------
	local mod = g_modManager:getModByName(self.name)
	self.version 	= mod.version or "0.0.0.0" 	-- FS22 version
	self.modSettings= g_modSettingsDirectory
	self.isServer 	= g_server ~= nil
	self.isClient 	= g_client ~= nil
	self.visible 	=	{"invisible", "visible", "visible"}
	self.isIcon 	=	{[false] = 	"icons";	[true]  =	"spots"}
	self.isRound	=	{[false] = 	g_i18n:getText("BS_square"); [true] = g_i18n:getText("BS_round")}
	self.icons 		=	{
			squareStraw	= self.directory.."HotspotIcons/square/StrawSquareBale.dds",
			squareHay	= self.directory.."HotspotIcons/square/HaySquareBale.dds",
			squareGrass	= self.directory.."HotspotIcons/square/GrassSquareBale.dds",
			squareSilage= self.directory.."HotspotIcons/square/SilageSquareBale.dds",
			squareCotton= self.directory.."HotspotIcons/square/CottonSquareBale.dds",
			roundStraw	= self.directory.."HotspotIcons/round/StrawRoundBale.dds",
			roundHay	= self.directory.."HotspotIcons/round/HayRoundBale.dds",
			roundGrass	= self.directory.."HotspotIcons/round/GrassRoundBale.dds",
			roundSilage	= self.directory.."HotspotIcons/round/SilageRoundBale.dds",

			beetPallet	= self.directory.."HotspotIcons/sugarbeet.dds",
			boards		= self.directory.."HotspotIcons/boards.dds",
			bread		= self.directory.."HotspotIcons/bread.dds",
			butter		= self.directory.."HotspotIcons/butter.dds",
			cake		= self.directory.."HotspotIcons/cake.dds",
			canolaOil	= self.directory.."HotspotIcons/canolaOil.dds",
			carrPallet	= self.directory.."HotspotIcons/carrot.dds",
			cereals		= self.directory.."HotspotIcons/cereals.dds",
			cheese		= self.directory.."HotspotIcons/cheese.dds",
			chocolate	= self.directory.."HotspotIcons/chocolate.dds",
			clothes		= self.directory.."HotspotIcons/clothes.dds",
			eggsPallet	= self.directory.."HotspotIcons/eggBox.dds",
			fabrics		= self.directory.."HotspotIcons/fabrics.dds",
			flourPallet	= self.directory.."HotspotIcons/flour.dds",
			furniture	= self.directory.."HotspotIcons/furniture.dds",
			grape 		= self.directory.."HotspotIcons/grapes.dds",
			grapeJuice	= self.directory.."HotspotIcons/grapeJuice.dds",
			honey		= self.directory.."HotspotIcons/honey.dds",
			lettuce		= self.directory.."HotspotIcons/lettuce.dds",
			milkPallet	= self.directory.."HotspotIcons/milk.dds",
			oliveOil	= self.directory.."HotspotIcons/oliveOil.dds",
			otherPallet	= self.directory.."HotspotIcons/oldPallet.dds",
			potatoPallet= self.directory.."HotspotIcons/potato.dds",
			raisin		= self.directory.."HotspotIcons/raisin.dds",
			strawberries= self.directory.."HotspotIcons/strawberries.dds",
			sugarBox	= self.directory.."HotspotIcons/sugarBox.dds",
			sunflowerOil= self.directory.."HotspotIcons/sunflowerOil.dds",
			tomato		= self.directory.."HotspotIcons/tomatoes.dds",
			woolPallet	= self.directory.."HotspotIcons/wool.dds",
						} 
	self.showOpts 	= {g_i18n:getText("ui_off"),g_i18n:getText("BS_icons"),g_i18n:getText("BS_symbols")}
	self.sizeOpts 	= {g_i18n:getText("configuration_valueSmall"), g_i18n:getText("setting_medium"), 
						   g_i18n:getText("configuration_valueBig")}
	self.ROUND 		= g_i18n:getText("fillType_roundBale")		   		   
	self.SQUARE 	= g_i18n:getText("fillType_squareBale")	
	if g_gui.languageSuffix == "_en" then 
		self.ROUND 	= self.ROUND .. "s"
		self.SQUARE	= self.SQUARE .. "s"
	end
	self.baleIdToHash= {}	   			-- to find bale type from bale.id   
	self.numBalTypes = {0,0,0,0,0,0,0,0}-- # of diff bale types per farm/ length of self.bales[i]
	self.numBales 	= {0,0,0,0,0,0,0,0}	-- total bales for each farm
	self.numPals 	= {0,0,0,0,0,0,0,0}	-- total pallets for each farm
	self.baleState	= BS.ICON			-- 1:off, 2:icon, 3:dot
	self.palState 	= BS.ICON 			-- 
	self.dispSize 	= 3					-- 1:small, 2:medium, 3:large
	self.statFarm 	= nil 				-- MP: farmId to display bale/pall stats
	self.showAll 	= false 			-- MP: show hotspots of all farms
	self.numShopMessage = 2 			-- MP: how often to show shop message, on remote bale buying
	self.symSizes 	= {
		{ icon = {getNormalizedScreenValues(20,20)},dot = {getNormalizedScreenValues(30,30)}},  --"small"
		{ icon = {getNormalizedScreenValues(30,30)},dot = {getNormalizedScreenValues(40,40)}},  --"medium"
		{ icon = {getNormalizedScreenValues(40,40)},dot = {getNormalizedScreenValues(60,60)}}  	--"large"
		}
	self.fileHotspots = PlaceableHotspot.FILENAME

	-- ---------------Helper functions------------------------
	source(self.directory.."scripts/helper.lua")
	-- ---------------Manage Hotspots for bales --------------
	source(self.directory.."scripts/hotspots.lua")
	------------------User interface / pallet functions ------
	source(self.directory.."scripts/userint.lua")

	--load settings from modSettings folder
	local key = "BaleSee"
	local f = self.modSettings .. 'FS22_SeeBales.xml'
	if fileExists(f) then
		local xmlFile = loadXMLFile("BaleSee", f, key);
		self.baleState =Utils.getNoNil(getXMLInt(xmlFile, key.."#baleState"), 2);			
		self.palState = Utils.getNoNil(getXMLInt(xmlFile, key.."#palState"), 2);			
		self.dispSize = Utils.getNoNil(getXMLInt(xmlFile, key.."#size"), 3);
		if not self.debug then 			
			self.debug =	Utils.getNoNil(getXMLBool(xmlFile, key.."#debug"), false);			
		end
		delete(xmlFile);
	end;
	debugPrint("read settings from: %s", f)
	debugPrint("** baleState: %d. palletState: %d. size: %d",
			self.baleState, self.palState, self.dispSize)

	if self.isClient then
	-- load "BSGui.lua", "BSGui.xml"
		if not self:loadGUI(true, self.directory.."gui/") then
			Logging.error(
			"'%s.Gui' failed to load! Supporting files are missing.", self.name)
			return
		end
	end
	-- to insert Shift-B key for player F1-menu
	Player.registerActionEvents = Utils.appendedFunction(Player.registerActionEvents, registerAction);
	Player.removeActionEvents = Utils.appendedFunction(Player.removeActionEvents, removeAction);		
		
	-- to render text with a hotspot
	PlaceableHotspot.render = Utils.overwrittenFunction(PlaceableHotspot.render, renderHotspot)
	-- to know when a bale was bought from store
	ShopController.onVehicleBought = Utils.appendedFunction(ShopController.onVehicleBought, baleBought);

	if self.debug then 
		-- to know when a bale creates on client
		NetworkNode.addObject = Utils.appendedFunction(NetworkNode.addObject, addBale);
		BuyVehicleEvent.run = Utils.appendedFunction(BuyVehicleEvent.run, buyEventRun);
	end
	self.initialized 	= true
	print(string.format("  Loaded %s V%s", self.name, self.version))
end;
function BaleSee:onLoad(mission)
	self.mission = mission
	self.accessHandler = mission.accessHandler
	self.isMultiplayer = mission.missionDynamicInfo.isMultiplayer
end;
----------------------- initilization on load Map ----------------------------------------------
function BaleSee:onPostLoadMap()
	debugPrint("-- BaleSee:loadMap() --") 
	self.shopX = g_currentMission.storeSpawnPlaces[1].startX
	self.shopZ = g_currentMission.storeSpawnPlaces[1].startZ 
	self.ft 			= g_fillTypeManager.fillTypes
	self.ingameMap 		= g_currentMission.inGameMenu.pageMapOverview.ingameMapBase
	self.ingameMap.filter[MapHotspot.CATEGORY_BALE] = true

	self.baleCols =	{  -- set this here, because FillType.x is not yet filled, outside of loadMap()
		-- the standard game bale types:
		[FillType.STRAW] =		{{0.6, 	0.3, 	0, 		1},	-- Orange
								 BS.BALES.."strawRound.png", 
								 BS.BALES.."straw.png"},
		[FillType.DRYGRASS_WINDROW] ={{0.4, 	1, 		0.4, 	1},	-- Light Green
								 BS.BALES.."dryGrassRound.png", 
								 BS.BALES.."dryGrass.png"},
		[FillType.SILAGE] =		{{0.95, 	0.35, 	0.35,	1},		-- pink
								 BS.BALES.."silageRound.png", 
								 BS.BALES.."silage.png"},
		[FillType.GRASS_WINDROW]={{0.1, 	0.2, 	0, 		1},		-- Dark Green
								 self.icons.roundGrass, self.icons.squareGrass}, 
		[FillType.COTTON] =		{{0.5, 	0.5, 	0.7,	1},			-- grey
								 self.icons.squareCotton, self.icons.squareCotton}
		}
	self.pallCols = {			-- {color, iconFilename, category}
		-- pallet farm supplies:
		[FillType.UNKNOWN] =	{{1, 	0, 		1, 		1},	self.icons.otherPallet,1},	-- Magenta
								 
		[FillType.PIGFOOD] =	{{0.27, 	0.085,	0.085, 	1},		-- dark pink
								 "data/objects/bigBagPallet/pigFood/store_bigBagPallet_pigFood.png", 1},
		[FillType.FERTILIZER] = {{0.55, 	0.25, 	0.25,	1},		-- medium pink
								 "data/objects/bigBagPallet/fertilizer/store_bigBagPallet_fertilizer.png", 1},
		[FillType.LIME] =		{{1, 	0.6, 	0.6, 	1},			-- light pink
								 "data/objects/bigBagPallet/lime/store_bigBagPallet_lime.png", 1},
		[FillType.WHEAT] =		{{0.55, 	0.5, 	0.26,	1},		-- light bronze
								 "data/objects/bigBagPallet/chickenFood/store_bigBagPallet_chickenFood.png", 1},
		[FillType.OAT] =		{{0.34, 	0.29, 	0.15,	1},		-- medium bronze	
								 "data/objects/bigBagPallet/horseFood/store_bigBagPallet_horseFood.png", 1},		
		[FillType.SEEDS] =		{{0.1, 	0.04, 	0.04, 	1},			-- dark brown
								 nil, 1},-- because SEEDS can also be a pallet. So we rely on the store item image
		[FillType.LIQUIDFERTILIZER] = {{0.79, 	0.6, 	0.3, 1},	-- light Orange
								 "data/objects/pallets/liquidTank/store_fertilizerTank.png", 1},
		[FillType.HERBICIDE] =	{{0.8, 	0.0, 	0.8,	1},			-- medium magenta	
								 "data/objects/pallets/liquidTank/store_herbicideTank.png", 1},
		[FillType.TREESAPLINGS]={{0, 	0.39, 	0.09,	1},			-- Green
								 "data/objects/pallets/treeSaplingPallet/store_pallet_saplings.png", 1},
		[FillType.SUGARCANE] =	{{0.014, 0.9, 	0.22,	1},			-- light Green
								 "data/objects/pallets/palletSugarCane/store_palletSugarCane.png", 1},
		[FillType.POPLAR] =		{{0.05, 	0.1, 	0.0,	1},		-- dark green
								 "data/objects/pallets/palletPoplar/store_pallet_saplingsPoplar.png", 1},
		[FillType.ROADSALT] =	{{0.62, 0.82, 0.92,1}, 				-- 43
								 "data/objects/bigBagPallet/roadSalt/store_bigBagPallet_roadSalt.png", 1},	 
		[FillType.MINERAL_FEED] =	{{0.62, 0.63, 0.39,1},  		-- 83
								 "data/objects/pallets/schaumann/store_schaumannPallet.png", 1},	-- 83 
		[FillType.SILAGE_ADDITIVE] ={{0.37, 0.48, 0.65,1},			-- 82
								 "data/objects/pallets/bonsilage/store_bonsilagePallet.png", 1},	-- 82 
		-- pallet farm products:
		[FillType.WOOL] =		{{0.69, 0.66, 0.7, 	1},	self.icons.woolPallet,2},	-- light grey
		[FillType.EGG] =		{{0.63, 0.38, 0.27,	1},	self.icons.eggsPallet,2},	-- light brown
		[FillType.MILK] =		{{0.59, 0.62, 0.62,	1},	self.icons.milkPallet,2},	-- light grey
		[FillType.POTATO] =		{{0.15, 0.05, 0.05,	1},	self.icons.potatoPallet,2},	-- light brown
		[FillType.SUGARBEET] =	{{0.5, 	0.3, 0.19,	1},	self.icons.beetPallet,2},	-- middle brown
		[FillType.SUGARBEET_CUT]={{0.5, 0.4, 0.19,	1},	self.icons.beetPallet,2},	-- middle brown
		[FillType.SUNFLOWER] =	{{0.9, 0.7, 0.1,	1},	self.icons.beetPallet,2},	-- middle yello
		[FillType.GRAPE] =		{{0.50, 0.30, 0.19,1}, self.icons.grape,2},		--  7 GRAPE
		[FillType.HONEY] =		{{0.93, 0.77, 0.00,1}, self.icons.honey,2},		-- 52 HONEY
		[FillType.LETTUCE] =	{{0.24, 0.64, 0.22,1}, self.icons.lettuce,2},	-- 59 LETTUCE
		[FillType.TOMATO] =		{{0.67, 0.01, 0.,  1}, self.icons.tomato,2},	-- 60 TOMATO
		[FillType.STRAWBERRY] =	{{0.9 , 0.02, 0.02,1}, self.icons.strawberries,2},-- 61 STRAWBERRY

		-- food products:
		[FillType.FLOUR] =		{{0.31, 0.42, 0.72,1}, self.icons.flourPallet,3},-- 44 FLOUR
		[FillType.SUGAR] =		{{0.  , 0.40, 0.75,1}, self.icons.sugarBox,3},	-- 51 SUGAR
		[FillType.RAISINS] =	{{0.68, 0.33, 0.18,1}, self.icons.raisin,3},	-- 57 RAISINS
		[FillType.GRAPEJUICE] =	{{0.40, 0.12, 0.58,1}, self.icons.grapeJuice,3},-- 58 GRAPEJUICE
		[FillType.CEREAL] =		{{1.  , 0.69, 0.00,1}, self.icons.cereals,3},	-- 53 CEREAL
		[FillType.SUNFLOWER_OIL]={{0.90,0.64, 0.02,1}, self.icons.sunflowerOil,3},-- 54 SUNFLOWER_OI
		[FillType.CANOLA_OIL] =	{{0.49, 0.46, 0.17,1}, self.icons.canolaOil,3},	-- 55 CANOLA_OIL
		[FillType.OLIVE_OIL] =	{{0.61, 0.58, 0.42,1}, self.icons.oliveOil,3},	-- 56 OLIVE_OIL
		[FillType.BREAD] =		{{0.75, 0.34, 0.05,1}, self.icons.bread,3},		-- 45 BREAD
		[FillType.CAKE] =		{{1.  , 0.79, 0.60,1}, self.icons.cake,3},		-- 46 CAKE
		[FillType.BUTTER] =		{{0.89, 0.64, 0.21,1}, self.icons.butter,3},	-- 47 BUTTER
		[FillType.CHEESE] =		{{0.93, 0.86, 0.46,1}, self.icons.cheese,3},	-- 48 CHEESE
		[FillType.CHOCOLATE] =	{{0.39, 0.21, 0.12,1}, self.icons.chocolate,3},	-- 62 CHOCOLATE

		-- industry products:
		[FillType.FABRIC] =		{{0.85, 0.01, 0.02,1}, self.icons.fabrics,4},	-- 49 FABRIC
		[FillType.CLOTHES] =	{{0.32, 0.36, 0.40,1}, self.icons.clothes,4},	-- 50 CLOTHES
		[FillType.BOARDS] =		{{0.60, 0.33, 0.  ,1}, self.icons.boards,4},	-- 63 BOARDS
		[FillType.FURNITURE] =	{{0.42, 0.05, 0.03,1}, self.icons.furniture,4},	-- 64 FURNITURE
								 
		}
	-- Carrot pallets [FS19]:
	local ft = g_fillTypeManager.nameToIndex["CARROT"]
	if ft ~= nil then
		self.pallCols[ft] = 	{{1, 0.4, 0.1, 1}, self.icons.carrPallet,2}		-- orange
	end	
	-- additional bale types (i.e. for maize+ extension)
	self:loadBaleTypes()

	-- keep bale/pall tables for each farm individually (MP)
	for i = 1,8 do
		self.bales[i]  = {[FillType.UNKNOWN] = {
							text = "unknown (n/a)" ,
							number = 0	}
						 }
		self.pallets[i]= {[FillType.UNKNOWN] = 0 }
	end
	-- needed to change vis of bale hotspots:
	g_messageCenter:subscribe(MessageType.PLAYER_FARM_CHANGED, self.onPlayerFarmChanged, self)
	g_messageCenter:subscribe(MessageType.FARM_DELETED, self.onFarmDeleted, self)

	if self.debug then
		self:makeLegend() 	-- needs self.colors
		addConsoleCommand("bsLegend", "Switch legend display on ingameMap [on / off].", "toggleLegend", self)
		addConsoleCommand("bsObjects", "Look for owned bales on client [balesOnly].", "cltObjects", self)
	end
end;
function BaleSee:onPostSaveSavegame(savegameDir, index)
	-- save my settings
	local key = "BaleSee"
	local f = self.modSettings .. 'FS22_SeeBales.xml'
	local xmlFile = createXMLFile("BaleSee", f, key);
	setXMLInt(xmlFile, key .. "#baleState", self.baleState);
	setXMLInt(xmlFile, key .. "#palState", 	self.palState);		
	setXMLInt(xmlFile, key .. "#size",		self.dispSize);
	if self.debug then
		setXMLBool(xmlFile, key .. "#debug",	self.debug);
	end
	saveXMLFile(xmlFile);
	delete(xmlFile);
	debugPrint("** BaleSee:saved settings to " ..f);
end
function BaleSee:updateHotspots(type)
	if type == "bale" then
		for _, item in pairs (self.mission.itemSystem.itemsToSave) do
			local ob = item.item
			local h = self.baleToHotspot[ob] 	-- {hotspot, color, fillType}
			if h ~= nil then 		
				-- we have already seen/ created hotspot for this bale. Just move the hotspot
				local x, y, z = getWorldTranslation(ob.nodeId)
				h[1]:setWorldPosition(x, z)	
				-- check filltype change - onFermentationEnd() :
				local fillType = ob:getFillType()
				if h[3] ~= fillType then 
					self:onChangedFillType(ob)
				end
				-- check wrapping state
				if ob.isFermenting and self.baleIdToHash[ob.id] > 0 then 
					-- grass bale has been wrapped, change its hash:
					self:onChangedFermenting(ob)
				end
			elseif ob.isa ~= nil and ob:isa(Bale) and ob:getOwnerFarmId() ~= nil
				and ob:getOwnerFarmId() ~= 0
			--	and self.accessHandler:canFarmAccessOtherId(self.farmId, ob:getOwnerFarmId()) 
				then
				self:makeBHotspot(ob)
			end
		end
	elseif type == "pallet" then
		for _, vehicle in ipairs (self.mission.vehicles) do
			local h = self.pallToHotspot[vehicle]  -- {hotspot,color,fillType}
			if h ~= nil then 		
				local x, y, z = getWorldTranslation(vehicle.rootNode)
				h[1]:setWorldPosition(x, z)
				-- check filltype change :
				local fillType = vehicle:getFillUnitFillType(1)
				if h[3] ~= fillType then 
					self:onChangedFillType(vehicle)
				end
			elseif vehicle.isa ~= nil and vehicle:isa(Vehicle)
				and string.find("pallet bigBag treeSaplingPallet", vehicle.typeName) 
				and vehicle:getOwnerFarmId() ~= 0 
			--	and vehicle:getPropertyState() ~= Vehicle.PROPERTY_STATE_SHOP_CONFIG
			--	and self.accessHandler:canFarmAccessOtherId(self.farmId, vehicle:getOwnerFarmId()) 
				then
				self:makePHotspot(vehicle)
			end
		end
	end
end
function BaleSee:onUpdate(dt)
	if self.isMultiplayer and g_dedicatedServer ~= nil then return end
	-- move our hotspots on the map. Detect new bales / pallets
	if self.baleState > BS.OFF then
		self:updateHotspots("bale")
	end	
	if self.palState > BS.OFF then
		self:updateHotspots("pallet")
	end	
end
function baleBought(shop, lease, price) --  ShopController:onVehicleBought()
	debugPrint("--baleBought: file %s price %d", shop.buyItemFilename:sub(-18),price)
	local bs = BaleSee
	if not (bs.isMultiplayer and bs.isClient) or bs.numShopMessage == 0 then return end  

	-- player far away from shop?
	local plX,_,plZ = getWorldTranslation(g_currentMission.player.rootNode)
	local distance = MathUtil.vector2Length(bs.shopX - plX, bs.shopZ - plZ)
	debugPrint("  player: (%.1f, %.1f), shop: (%.1f, %.1f), dist %.1f",
		plX,plZ, bs.shopX,bs.shopZ, distance)
	if shop.buyItemFilename:find("buyableBales") and distance > 300 then 
		-- 300 is forcedClipDistance for a bale
		local text = g_i18n:getText("BS_baleBought")
		if bs.numShopMessage == 1 then 
			text = text .."\n\n"..  g_i18n:getText("BS_lastBought")
		end
		bs.numShopMessage = bs.numShopMessage -1
		g_gui:showInfoDialog({
			text = text,
			dialogType = DialogElement.TYPE_INFO,
			callback = shop.onBoughtCallback,
			target = shop
		})
	end
end
function addBale(node, obj, id)
	-- called when client first sees a bale obj
	-- need this for bales created far away from player (e.g. store buy)
	if g_server or not obj:isa(Bale) then return end
	local bs = BaleSee
	-- skip if client is still joining the game 
	if not bs.mission.isMissionStarted then return end

	debugPrint("- addObject(): %s / %s", obj.id, id)
	-- create hotspot, if this bale does not have one yet
	local hs, col, img 
	local h = bs.baleToHotspot[obj] 	-- {hotspot, color, fillType}
	if h == nil and obj:getOwnerFarmId() ~= nil
				and obj:getOwnerFarmId() ~= 0 then
		bs:makeBHotspot(obj)
	end	
end
function buyEventRun(evt, connection) -- BuyObjectEvent:run()
	debugPrint("--BuyObjectEvent, server connection = %s", connection:getIsServer())
	debugPrint("file %s. farmId %s. errorCode %s", evt.filename:sub(-18),
		evt.ownerFarmId, evt.errorCode)
	--if not connection:getIsServer() then
end
