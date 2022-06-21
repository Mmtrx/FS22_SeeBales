--=======================================================================================================
--  BALESEE USER INTERFACE FUNCTIONS
--
-- Purpose:		Allows bales and pallets to show up on the PDA map as hotspots.
-- Author:		Mmtrx		
-- Changelog:
--  v1.0		03.01.2019	original FS17 version by akuenzi (akuenzi@gmail.com)
--	v1.1.0		28.08.2019	updates for FS19, added user interface  
--  v1.1.1		17.09.2019  added pallette support.
--  v1.1.2		08.10.2019	save statistics / add legend in debug mode 
--  v2.0.0		10.02.2020  add Gui (settings and statistics)
--  v2.1.0.0	30.06.2021  MULTIPLAYER! / handle all bale types, (e.g. Maizeplus forage extension)
--  v3.0.0.1	15.06.2022  bale / pallet detection moved to update(dt). Inspired by GtX EDC
--=======================================================================================================
-------------------- Load functions ------------------------------------------------------------
function BaleSee:loadBaleTypes()
	-- load additional bale types from modDesc.xml
	local modDesc = loadXMLFile("modDesc", self.directory.."modDesc.xml")
	local i, ftName, colText, fround, fsquar, baleKey 
	local function rgbNormalize( colText )
		-- return FS19 normalized rgb values 
		local vals = StringUtil.splitString(" ",colText)
		for i = 1, #vals do
			vals[i] = (tonumber(vals[i])/255)^2.2
		end
		vals[4] = 1
		return unpack(vals)
	end;
	i = 0
	while true do
		baleKey = string.format("modDesc.baleTypes.bale(%d)", i)
		if not hasXMLProperty(modDesc, baleKey) then break; end;
		
		ftName = Utils.getNoNil(getXMLString(modDesc, baleKey .. "#name"), "")
		ft = g_fillTypeManager.nameToIndex[ftName]
		if ft == nil then
			if self.debug then print(string.format("-- bale type %s ignored.",ftName)) end
		elseif self.baleCols[ft] == nil then 	-- we have not seen this bale type yet
			colText = Utils.getNoNil(getXMLString(modDesc, baleKey .. "#color"), "255 0 255")
			fround = self.directory..Utils.getNoNil(getXMLString(modDesc, baleKey .. "#round"), "")
			fsquar = self.directory..Utils.getNoNil(getXMLString(modDesc, baleKey .. "#square"), "")
			if fileExists(fround) then
				if not fileExists(fsquar) then fsquar = fround end
				self.baleCols[ft] = {
					{rgbNormalize(colText)},
					fround, fsquar
				}
			else 
				Logging.error("%s: Icon file '%s' for bale type '%s' not found.",
					self.name,fname,ftName)	
			end	
		end	
		i = i +1
	end
	delete(modDesc)
end;
function BaleSee:loadGUI(canLoad, guiPath)
	if canLoad then
		-- load "BSGui.lua"
		if g_gui ~= nil and g_gui.guis.BSGui == nil then
			local luaPath = guiPath .. "BSGui.lua"
			if fileExists(luaPath) then
				source(luaPath)
			else
				canLoad = false
				Logging.error("[GuiLoader %s]  Required file '%s' could not be found!", 
					self.name, luaPath)
			end
		-- load "BSGui.xml"
			if canLoad then
				-- load my gui profiles 
				g_gui:loadProfiles(guiPath .. "guiProfiles.xml")
				local xmlPath = guiPath .. "BSGui.xml"
				if fileExists(xmlPath) then
					self.oGui = BSGui.new(nil, nil) 		-- my Gui object controller
					g_gui:loadGui(xmlPath, "BSGui", self.oGui)
				else
					canLoad = false
					Logging.error("[GuiLoader %s]  Required file '%s' could not be found!", 
						self.name, xmlPath)
				end
			end
		end
	end
	return canLoad
end;
-------------------- User interface functions ---------------------------------------------------
function BaleSee:onPlayerFarmChanged(player)
	-- body
	if player == g_currentMission.player then
		local farmId = player.farmId or FarmManager.SPECTATOR_FARM_ID
		if self.showAll then return end

		if self.baleState > BS.OFF then 
			for i=1,8 do
				self:toggleVis(self.bHotspots[i], false)
			end
			-- show only hotspots for own farm:
			if farmId > FarmManager.SPECTATOR_FARM_ID then
				self:toggleVis(self.bHotspots[farmId], true)
			end
		end	
	end
end
function BaleSee:onFarmDeleted(farmId)
	-- delete hotspots (and bales!) for this farm 
	-- also called when leaving game (deletes spectator farm)
	if farmId == nil or farmId == 0 then return end
	if not self.isClient or self.numBales[farmId] < 1 then return end
	debugPrint("farm %d %s deleted", farmId, g_farmManager:getFarmById(farmId))

	for h, v in pairs(self.bHotspots[farmId]) do
		-- v is {bale, color, filltype}. Std game doesn't delete farms bales (error?)
		v[1]:delete()
	end
end
function BaleSee:registerActionEventsPlayer()
	-- gets called when player leaves vehicle
	local bs = BaleSee
	local result, eventId = InputBinding.registerActionEvent(g_inputBinding,"bs_Bale",
			self,bs.actionbs_Bale,false,true,false,true)
	if result then
		bs.event = eventId
		g_inputBinding.events[eventId].displayIsVisible = true;
	end
end;
function BaleSee:removeActionEventsPlayer()
	-- gets called when player enters vehicle
	BaleSee.event = nil
end;
function BaleSee:actionbs_Bale(actionName, keyStatus, arg3, arg4, arg5)
	local bs = BaleSee
	-- set texts for multiTextOption Gui elements:
	bs.oGui.setShowBales:setTexts(bs.showOpts)
	bs.oGui.setShowBales:setState(bs.baleState)

	bs.oGui.setShowPals:setTexts(bs.showOpts)
	bs.oGui.setShowPals:setState(bs.palState) 		--, true)

	bs.oGui.setSize:setTexts(bs.sizeOpts)
	bs.oGui.setSize:setState(bs.dispSize) 			--, true)

	bs.oGui.setFarm:setVisible(bs.isMultiplayer)
	bs.oGui.setAll:setVisible(bs.isMultiplayer)
	if bs.isMultiplayer then
		bs.statFarm = g_currentMission:getFarmId()
		local statIx
		local texts = {}
		local farms = g_farmManager:getFarms()
		if #farms < 2 then -- only spectator farm avail
			g_gui:showInfoDialog({
			text = string.format(g_i18n:getText("ui_noFarmsCreated"), self.name)
			})
			return
		end
		for i = 2,#farms do
			texts[i-1] = farms[i].name
			bs.oGui.farmIds[i-1] = farms[i].farmId
			if bs.statFarm == farms[i].farmId then 
				statIx = i-1
			end
		end	
		bs.oGui.setFarm:setTexts(texts)
		-- multitext index of statFarm
		if statIx == nil then  	-- in case bs.statFarm is 0 or nil
			statIx = 1
			bs.statFarm = farms[2].farmId
		end
		bs.oGui.setFarm:setState(statIx)

		-- "show all" setting:
		bs.oGui.setAll:setTexts({g_i18n:getText("ui_yes"), g_i18n:getText("ui_no")})
		bs.oGui.setAll:setState(bs.showAll and 1 or 2) 			
	end	
	-- show Gui
	if g_gui:showDialog("BSGui") == nil then
		Logging.error("%s could not show Gui!", bs.name)
	end
end;
