--=======================================================================================================
--  BALESEE HELPER FUNCTIONS
--
-- Purpose:		Allows bales and pallets to show up on the PDA map as hotspots.
-- Author:		Mmtrx		
-- Changelog:
--  v1.0		03.01.2019	original FS17 version by akuenzi (akuenzi@gmail.com)
--	v1.1.0		28.08.2019	updates for FS19, added user interface  
--  v1.1.1		17.09.2019  added pallette support.
--  v1.1.2		08.10.2019	save statistics / add legend in debug mode 
--  v2.0.0		10.02.2020  add Gui (settings and statistics)
--  v2.0.0.1	19.06.2020  handle all pallet types, (e.g. straw harvest)
--  v2.1.0.0	30.06.2021  MULTIPLAYER! / handle all bale types, (e.g. Maizeplus forage extension)
--  v3.0.0.1	15.06.2022  bale / pallet detection moved to update(dt). Inspired by GtX EDC
--=======================================================================================================
function BaleSee:getSize(typ, size)
	-- return icon / dotmarker size in u.v coordinates
	if size == nil then size = self.dispSize end
	local isiz = self.symSizes[size]
	return unpack(isiz[typ])
end;
function BaleSee:getColor(object)
	-- return color depending on filltype of bale/ pallet object 
	local ret = {1,1,1,1} 				-- default
	local ft = object.fillType 		-- works, if it's a bale

	if ft == nil then 					-- it's a pallet, vehicle object.
		ft = object:getFillUnitFillType(1)
		if self.pallCols[ft] ~= nil and self.pallCols[ft][1] ~= nil then
			ret = self.pallCols[ft][1]
		end
	elseif self.baleCols[ft] ~= nil and self.baleCols[ft][1] ~= nil then
			ret = self.baleCols[ft][1]
	end
	return ret 		
end;
function BaleSee:getBImage(bale)
	-- return icon image depending on filltype of bale object
	local image   = self.icons.roundGrass -- default image
	local fill 	  = bale:getFillType()
	
	-- select correct image, based on filltype
	if self.baleCols[fill] ~= nil then
		if bale.diameter > 0 and self.baleCols[fill][2] ~= nil then
			image = self.baleCols[fill][2] 
		elseif self.baleCols[fill][3] ~= nil then 
			image = self.baleCols[fill][3] 
		end			
	end
	return image
end;
function BaleSee:getPImage(object, ft)
	-- find image source for the PALLET icon display
	local image = self.icons.otherPallet --default image
	
	-- shop item pallets / bigBags:
	if object.configFileName then
		local storeItem = g_storeManager:getItemByXMLFilename(object.configFileName)
		if storeItem and storeItem.imageFilename and not 
			storeItem.imageFilename:find("store_empty") then
			return storeItem.imageFilename
		end
	end
	-- production pallets (eggs, wool, tomato, lettuce, ..)
	if ft ~= nil and self.pallCols[ft] ~= nil and self.pallCols[ft][2] ~= nil then
		return self.pallCols[ft][2]
	end
	return image
end
function BaleSee:toggleVis(spots, on)
	-- show / hide some map hotspots
	for h, _ in pairs(spots) do
		h.isVisible = on
		h.enabled = on
		h.hasDetails = on
	end
end;
function BaleSee:toggleCol(spots, on, forPallets)
	local size = self.dispSize
	-- for each hotspot in spots: toggle its icon
	local whatState = "baleState"
	if forPallets then whatState = "palState" end 

	for h, _ in pairs(spots) do
		-- set icon to image
		h.icon = h.images[size] 
		h.clickArea = h.clickIcon
		-- set icon to dotmarker
		if self[whatState] == BS.DOT then 
			h.icon = h.dots[size] 
			h.clickArea = h.clickDot
		end
	end
end;
function BaleSee:toggleSize(size)
	-- set size for existing map hotspots
	local hs 
	if size == nil then size = self.dispSize end
	-- we set sizes for icon if baleState OFF
	for farm = 1,8 do
		for hs, _ in pairs(self.bHotspots[farm]) do
			hs.icon = hs.images[size] 
			if self.baleState == BS.DOT then hs.icon = hs.dots[size] end
			hs.icon:resetDimensions() 		-- reset hud scaling effects
		end
	end
	-- for pallets:
	for hs, _ in pairs(self.pHotspots) do
		hs.icon = hs.images[size] 
		if self.palState == BS.DOT then hs.icon = hs.dots[size] end
		hs.icon:resetDimensions() 		-- reset hud scaling effects
	end
end;
function BaleSee:updBales(object,farmId,ft,inc,fermenting)
	-- adjust count in self.bales[farm]. 
	local isRound = object.diameter > 0 		-- works, if it's a bale
	local size = object.length *100 			-- length in cm
	if isRound then size = object.diameter *100 end
	local hash = 100000* (isRound and 1 or 0) + 100* ft + math.floor(size/10)
	if object.isFermenting then hash = -hash end 

	if self.bales[farmId] [hash] == nil then
		local ferm = ")"
		if object.isFermenting then ferm = " fm)" end 
		debugPrint("** new bale fillType (%d%s %s for farm %d. Hash: %d",
					ft, ferm, self.ft[ft].name,farmId,hash)

		self.bales[farmId][hash] = {
		 text = string.format("%s (%s %d%s", self.ft[ft].title, 
		 		self.isRound[isRound], size, ferm),
		 number = 0}
		self.numBalTypes[farmId] = self.numBalTypes[farmId] + 1	 -- update # bale types
	end
	if inc > 0 then 
		self.baleIdToHash[object.id] = hash 
	else
		self.baleIdToHash[object.id] = nil 
		if fermenting then hash = -hash end 
	end
	self.bales[farmId][hash].number = self.bales[farmId][hash].number +inc  -- update bale type
	self.numBales[farmId] = 		self.numBales[farmId] + inc	 			-- update bales sum
	return hash, self.bales[farmId][hash].text
end;
function BaleSee:updPallets(ft, farm, inc)
	-- adjust count in self.pallets[farm] 
	if farm == nil then 
		Logging.error("**SeeBales: Pallet %s has no farm.", object.rootNode)
		return
	elseif farm == 0 then
		Logging.warning("%s: Pallet %s has farm 0, will be ignored.", self.name, object.rootNode)
	end	
	--local ft = object:getFillUnitFillType(1)
	if self.pallets[farm][ft] == nil then
		self.pallets[farm][ft] = 0
		debugPrint("-- new pallet fillType %d %s",ft,self.ft[ft].name)
	end
	self.pallets[farm][ft] = self.pallets[farm][ft] +inc  -- update pallet type
	debugPrint("--updPallets(%s, %d, %d): updated pallets[%s]",
		ft,farm,inc,self.ft[ft].name)
	self.numPals[farm] = self.numPals[farm] + inc	 	-- update pallets sum
end;
----------------------- debug / development functions -------------------------------
function BaleSee:makeLegend()
	-- show all bale/pallet hotspot markers:
	local w,h = getNormalizedScreenValues(16,16)
	local x,z = -1000, -1000
	local files = self.icons
	local hotspot, image, icon
	local color = {}
	local function isbale( ft )		-- true if ft is bale fillType
		return self.baleCols[ft] ~= nil
	end;

	local ct = 1
	for i=1,#self.ft do
		if self.baleCols[i] ~= nil or self.pallCols[i] ~= nil then 
			-- ------------ dot: --------------------------------------
			icon = Overlay.new(self.fileHotspots, 0, 0, self:getSize("dot", 3)) 
			if isbale(i) then
				color, image, _ = unpack(self.baleCols[i])
				hotspot = BaleSeeHotspot.new("bale", image,
					string.format("%2d %s", i, self.ft[i].name) )
				icon:setUVs(GuiUtils.getUVs({652,4,100,100},PlaceableHotspot.FILE_RESOLUTION))
			else 	-- pallet:
				color, image = unpack(self.pallCols[i])
				hotspot = BaleSeeHotspot.new("pallet", image,
					string.format("%2d %s", i, self.ft[i].name) )
				icon:setUVs(GuiUtils.getUVs({220,111,100,100},PlaceableHotspot.FILE_RESOLUTION))
			end			
			icon:setColor(unpack(color))
			hotspot.icon = icon 
			hotspot:setWorldPosition(x, z)			-- also sets the x,z MapPos
			hotspot.enabled = false
			hotspot:setVisible(false)
			table.insert(self.legend, hotspot) 
			hotspot.legend = true
			g_currentMission:addMapHotspot(hotspot) 

			-- ------------ icon: -------------------------------------
			hotspot = BaleSeeHotspot.new("bale", image, self.ft[i].name)
			hotspot.icon = Overlay.new(image, 0, 0, self:getSize("icon", 3)) 
			hotspot.icon:setUVs(GuiUtils.getUVs({1,1,127,127},{128,128}))
			hotspot:setWorldPosition(x+40, z)	
			hotspot.enabled = false
			hotspot:setVisible(false)
			table.insert(self.legend, hotspot) 	-- need only the hotspot for toggleLegend
			g_currentMission:addMapHotspot(hotspot) 

			z = z +70	
			ct = ct +1
			if math.fmod(ct,28) == 1 then 
				-- start new column
				x = x + 200
				z = -1000
			end
		end				
	end;
end;
function BaleSee:toggleLegend(on)
	-- show/ hide legend display on ingameMap
	if on == nil then on = "on" end
	local vis = on == "on" 
	for _,h in ipairs(self.legend) do
		h:setVisible(vis)
	end
end;
function BaleSee:cltObjects( balesOnly )
	-- console cmd: find out bale objects that client sees
	if balesOnly == nil then balesOnly = false end
	if g_server then 
		print("  i  id  node farm type *SERVER objects")
		for i, o in pairs(g_server.objects) do
			if not balesOnly or o:isa(G0.Bale) then
				print(string.format("%3d %3d %5s %4s %s",i, o.id, tostring(o.nodeId),
					 tostring(o.ownerFarmId),tostring(o.typeName)))
			end
		end
		return 
	end
	print("  i  id  node farm type *CLIENT")
	for i, o in pairs(g_client.objects) do
		if not balesOnly or o:isa(G0.Bale) then
			print(string.format("%3d %3d %5s %4s %s",i, o.id, tostring(o.nodeId),
				 tostring(o.ownerFarmId),tostring(o.typeName)))
		end
	end
end;
function BaleSee.readStream(bale, superFunc, streamId, connection )
	-- only called during debug / development
	local bs = BaleSee
	local super = true
	if bale.fillType == nil then bale.fillType = 0 end
	-- do we see this for the 1st time?
	if g_client.objectIds[bale] == nil then
		superFunc(bale, streamId, connection)	
		super = false
		local cltBalId = g_client:getObjectId(bale)
		print(string.format("-- readStream: %s Bale %s %s/%s (%sl) of farm %s", 
			bs.ft[bale.fillType].name, cltBalId, bale.id,
			tostring(bale.nodeId), tostring(bale.fillLevel), tostring(bale.ownerFarmId)))
	end	
	
	if super then superFunc(bale, streamId, connection)	end
	local x,z = 0,0
	if bale.nodeId then x,_,z = getWorldTranslation(bale.nodeId) end
	print(string.format("-- %s %s %s Bale %s/%s (%sl) of farm %s at %4.2f %4.2f.", 
		bs.visible[bs.baleState], "n/a",
		bs.ft[bale.fillType].name, tostring(bale.id),
		tostring(bale.nodeId), tostring(bale.fillLevel), tostring(bale.ownerFarmId), x, z))	
end;
