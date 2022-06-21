--=======================================================================================================
--  BALESEE HOTSPOT FUNCTIONS
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
-- ---------------Hotspot class -----------------------------------------------------------
BaleSeeHotspot = {}
MapHotspot.CATEGORY_BALE = 16 
InGameMenuMapFrame.HOTSPOT_VALID_CATEGORIES[MapHotspot.CATEGORY_BALE] = true 

local BaleSeeHotspot_mt = Class(BaleSeeHotspot, PlaceableHotspot)

function BaleSeeHotspot.new(type, image, name)
	local self = PlaceableHotspot.new(BaleSeeHotspot_mt)
	--self.width, self.height = getNormalizedScreenValues(60, 60)
	self.bsType = type or "bale"
	self.hasRotation = type == "bigBag"
	if self.bsType == "bale" then 
		self.clickIcon = MapHotspot.getClickArea({100,40,312,200}, {512,512}, 0)
	else
		self.clickIcon = MapHotspot.getClickArea({80,10,380,320}, {512,512}, 0)
	end
	self.clickDot = MapHotspot.getClickCircle(0.2)
	self.baleSee = true
	self.bsImage = image
	self.name = name 
	self.ownerFarmId = AccessHandler.EVERYONE
	-- make fake placeable, called by InGameMenuMapFrame:setMapSelectionItem()
	-- when drawing map hotspots
	self.placeable = {
		hs = self, 
		getOwnerFarmId = function(se) return se.hs.ownerFarmId end,
		getImageFilename = function(se) return se.hs.bsImage end
	}
	return self
end
function BaleSeeHotspot:getCanBeAccessed()
	return true -- always allow clickin on hotspot
end
function BaleSeeHotspot:getCategory()
	return MapHotspot.CATEGORY_BALE -- outside of normal MapHotspot categories
end
function BaleSeeHotspot:getWorldRotation()
	local bs = BaleSee
	-- turn bigBag markers upside down:
	if self.hasRotation and bs.palState == BS.DOT then 
		return math.pi 
	else
		return 0 
	end
end
function BaleSee:delhot(hotspot, farm, isPallet)
	-- delete a hotspot
	if hotspot ~= nil then
		for _,icon in ipairs(hotspot.images) do icon:delete() end
		for _,icon in ipairs(hotspot.dots) do icon:delete() end
		hotspot.icon = nil
		g_currentMission:removeMapHotspot(hotspot)

		if isPallet then	-- delete a pallet hotspot
			self.pHotspots[hotspot] = nil
		else 				-- delete a bale hotspot
			self.bHotspots[farm][hotspot] = nil
		end
		hotspot:delete()		
	end
end;
function renderHotspot(hot,superFunc, x, y, rotation, small)
	if not hot:isa(BaleSeeHotspot) then 
		superFunc(hot, x, y, rotation, small)
		return
	end
	superFunc(hot, x, y, rotation, false) 	-- don't render our hotspots in minimap
	if BaleSee.debug and hot.legend then  
		-- render text below hotspot
		setTextBold(false)
		setTextAlignment(RenderText.ALIGN_LEFT)

		local posX = x 			--+ (0.5 * self.width + self.textOffsetX)
		local posY = y - 0.012
		--local textWidth = getTextWidth(self.textSize * self.zoom * scale, self.fullViewName) + 1 / g_screenWidth

		setTextColor(0, 0, 0, 1)
		renderText(posX, posY - 1 / g_screenHeight, 0.012, hot.name)
		setTextColor(1, 1, 1, 1)
		renderText(posX + 1 / g_screenWidth, posY, 0.012, hot.name)
	end
end

-- ----------------Manage Hotspots for bales.--------------------------------------------------
function BaleSee:onDeleteBale(bale)
	local bs = self
	local hash = bs.baleIdToHash[bale.id]
	local farm = bale:getOwnerFarmId()
	if hash == nil then
		debugPrint("** SeeBales: trying to delete unknown bale id %s",bale.id)
	elseif farm == nil or farm == 0 then
		debugPrint("** SeeBales: trying to delete bale id %s for unknown farm %s",
			bale.id, farm)
	else
		bs.bales[farm][hash].number = bs.bales[farm][hash].number -1
		bs.numBales[farm] = bs.numBales[farm] -1
		bs:delhot (bale.mapHotspot, farm)
		self.baleToHotspot[bale] = nil
	end
end;
function makeOverlays(image, color, type, imagesOnly)
	-- generate 3 overlays (small/med/large) for both dots and images
	if type == nil or not string.find("bale pallet bigBag", type) then 
		type = "bale"
	end
	local dots, images, icon = {}, {}
	local bs = BaleSee
	-- Hotspots will be small images:
	for i=1,3 do
		icon = Overlay.new(image, 0, 0, bs:getSize("icon", i)) 
		icon:setUVs(GuiUtils.getUVs({1,1,127,127},{128,128}))
		table.insert(images, icon)
	end
	-- Hotspots will be small colored circles:
	if imagesOnly then 
		return images 
	end
	for i=1,3 do
		icon = Overlay.new(bs.fileHotspots, 0, 0, bs:getSize("dot", i)) 
		-- pallet symbol:
		icon:setUVs(GuiUtils.getUVs({220,111,100,100},PlaceableHotspot.FILE_RESOLUTION))
		if type == "bale" then -- bale symbol
			icon:setUVs(GuiUtils.getUVs({652,4,100,100},PlaceableHotspot.FILE_RESOLUTION))
		end
		icon:setColor(unpack(color))
		table.insert(dots, icon)
	end
	return images, dots
end
function makeName(bale)
	local sep = 	" "
	if g_gui.languageSuffix == "_de" then sep = "-" end
	local unit = g_i18n:getText("unit_bale")
	if g_gui.languageSuffix == "_en" then unit = unit:sub(1,-2) end
	local nam = string.format("%s%s%s",BaleSee.ft[bale:getFillType()].title,sep,unit)
	if BaleSee.debug then 
		nam = nam .. string.format(" %s", bale.id)
	end
	return nam
end
function BaleSee:makeBHotspot( bale )
	-- create map hotspot for bale object
	local bs = self
	local isRoundbale = bale.diameter and bale.diameter > 0
	local farmId = bale:getOwnerFarmId()
	local x,y,z = getWorldTranslation(bale.nodeId)
	debugPrint("-- makeBHotspot(): %s %s %s Bale %d/%s (%sl) of farm %s at %4.2f %4.2f.", 
			bs.visible[bs.baleState], bs.isRound[isRoundbale],
			bs.ft[bale.fillType].name, bale.id,
			tostring(bale.nodeId), tostring(bale.fillLevel), tostring(farmId), x, z)	
	if farmId == nil then return end -- bale load in store

	local color = 	bs:getColor(bale)
	local image = 	bs:getBImage(bale)
	local nam   =	makeName(bale)

	-- Generate bale hotspot. 
	local hotspot = BaleSeeHotspot.new("bale",image,nam)

	-- generate possible icons for this hotspot:
	hotspot.images, hotspot.dots = makeOverlays(image, color, "bale") 

	hotspot.icon = hotspot.dots[bs.dispSize]
	hotspot.clickArea = hotspot.clickDot
	if bs.baleState == BS.ICON then
		hotspot.icon = hotspot.images[bs.dispSize]
		hotspot.clickArea = hotspot.clickIcon
	end
	local isVis = not self.isMultiplayer
	isVis = isVis or self.showAll or farmId==g_currentMission:getFarmId()
	hotspot:setVisible(isVis and bs.baleState > BS.OFF)				
	hotspot:setWorldPosition(x, z)			-- sets the x,z MapPos
	hotspot:setOwnerFarmId(farmId)
	g_currentMission:addMapHotspot(hotspot) 

	bale.mapHotspot = hotspot 				-- property of the bale object
	bale:addDeleteListener(self, "onDeleteBale")
	self.bHotspots[farmId][hotspot] = {bale, color, bale.fillType}
	self.baleToHotspot[bale] = {hotspot, color, bale.fillType}
	-- update count for this bale type
	local hash,txt = bs:updBales(bale, farmId, bale:getFillType(), 1)
end;
function BaleSee:onChangedFermenting(obj)
	-- a grass bale has been wrapped -> change hash to -hash. No change to hotspot
	-- incr fermenting grass type:
	local farm = obj:getOwnerFarmId()
	local hash, _ = self:updBales(obj, farm, obj:getFillType(), 1)	
	-- decrease plain grass type
	self.bales[farm][-hash].number = self.bales[farm][-hash].number -1  
	self.numBales[farm] = self.numBales[farm] -1
end

-- ----------------Manage Hotspots for pallets.--------------------------------------------------
function BaleSee.pal:onDelete(pall)		-- is called on delete for a pallet type object
	local bs = BaleSee
	local farm = pall:getOwnerFarmId()
	local fillType = bs.pallToHotspot[pall][3]
	if bs.debug then
		local typ = 	 pall.typeName
		print(string.format("-- onDelete %s %s %d farm %s",
			bs.ft[fillType].name, typ, pall.rootNode, tostring(farm)))
	end
	if farm == nil then return end 	-- from pallet load in store
	-- if farm == 0 ?

	-- decrease count for this farm /pallet type:
	bs:updPallets(fillType, farm, -1)

	-- remove hotspot from ingameMap and our own List
	bs:delhot (pall.mapHotspot, farm, true)
	bs.pallToHotspot[pall] = nil
end;
function BaleSee:makePHotspot(pall)
	-- create map hotspot for a pallet / bigBag
	local bs = 			BaleSee
	local nodeId = 		pall.rootNode
	if nodeId == nil then return end 	-- when object not yet complete (clt join)
	local x,y,z = 		getWorldTranslation(nodeId)
	local farmId = 		pall:getOwnerFarmId()
	if farmId == nil or farmId == 0 or x == .0 and z == .0 	-- pallet load in store
		or pall:getFillUnits() == nil  						-- obj not complete yet
		then return end 

	local fillType = 	pall:getFillUnitFillType(1)
	local image = 		bs:getPImage(pall,fillType)
	local color = 		bs:getColor(pall)
	local nam = 		bs.ft[fillType].title
	debugPrint("-- %s %s %s %d farm %s at %4.2f %4.2f", 
			bs.visible[bs.palState], bs.ft[fillType].name, pall.typeName,
			nodeId, tostring(farmId), x, z)

	-- Generate pallet hotspot. 
	local hotspot = BaleSeeHotspot.new(pall.typeName, image, nam)
	
	-- generate possible icons for this hotspot:
	hotspot.images, hotspot.dots = makeOverlays(image, color, pall.typeName) 

	hotspot.icon = hotspot.dots[bs.dispSize]
	hotspot.clickArea = hotspot.clickDot
	if bs.palState == BS.ICON then
		hotspot.icon = hotspot.images[bs.dispSize]
		hotspot.clickArea = hotspot.clickIcon
	end
	hotspot:setWorldPosition(x, z)			-- sets the x,z MapPos
	hotspot:setOwnerFarmId(farmId)
	hotspot:setVisible(bs.palState > BS.OFF)				
	g_currentMission:addMapHotspot(hotspot) 
	
	pall.mapHotspot = hotspot 				-- property of the pallet object
	pall:addDeleteListener(self.pal, "onDelete")
	bs.pHotspots[hotspot] = {pall,color,fillType} 
	bs.pallToHotspot[pall] = {hotspot,color,fillType}
	-- increase count for this pallet type:
	bs:updPallets(fillType, farmId, 1)
end;
function BaleSee:onChangedFillType(obj)
	--[[
		-(deprecated:) to set fillType of newly filled fillablePallet (egg / wool / potato / sugarbeet)
		 also, when selling/ feeding pallets, they change back to UNKNOWN when emptied, shortly 
		 before they get deleted
		-used for wrapped grass bales, when fermenting ends -> change to silage
	]]
	local bs = self
	local isPall = not obj:isa(Bale)
	local fillType, h, node, image, whatState
	if isPall then 
		node = obj.rootNode
		fillType = obj:getFillUnitFillType(1) 
		h = bs.pallToHotspot[obj] 		-- {hotspot,color,fillType}
		image = bs:getPImage(obj,fillType)
		h[1].name = bs.ft[fillType].title
		whatState = "palState"
	else 
		node = obj.nodeId
		fillType = obj:getFillType()
		h = bs.baleToHotspot[obj] 		-- {hotspot,color,fillType}
		image = bs:getBImage(obj)
		h[1].name = makeName(obj)
		whatState = "baleState"
	end
	if h == nil then return; end 		-- only for our managed pallets

	local oldFillType = h[3]
	debugPrint("-- filltype change for %s object %d to %s. Image: %s", 
		bs.ft[oldFillType].name,
		node, bs.ft[fillType].name, image)

	local hotspot = h[1]
	local color = bs:getColor(obj) 

	hotspot.bsImage = image 					-- change image for details display
	for _,icon in ipairs(hotspot.images) do
		icon:delete()
	end
	hotspot.images = makeOverlays(image, color, nil, true)

	for _,icon in ipairs(hotspot.dots) do  		-- change color of dots
		icon:setColor(unpack(color))
	end
	if bs[whatState] == BS.ICON then
		hotspot.icon = hotspot.images[bs.dispSize] 	-- change small image/icon.
	else
		hotspot.icon:setColor(unpack(color))
	end;
	-- change also in our tables of hotspots:
	local farm = obj:getOwnerFarmId()
	if isPall then
		bs.pHotspots[hotspot] = {obj, color, fillType}
		bs.pallToHotspot[obj] = {hotspot, color, fillType}
		-- adjust pallet counts, old filltype -1, new fillType +1:
		bs.pallets[farm][oldFillType] = bs.pallets[farm][oldFillType] -1
		if bs.pallets[farm][fillType] == nil then
			bs.pallets[farm][fillType] = 1 		-- we have a new filltype
		else
			bs.pallets[farm][fillType] = bs.pallets[farm][fillType] +1
		end
	else
		bs.bHotspots[hotspot] = {obj, color, fillType}
		bs.baleToHotspot[obj] = {hotspot, color, fillType}
		-- adjust bale counts, old filltype -1, new fillType +1:
		bs:updBales(obj, farm, oldFillType , -1, true)	-- decr old filltype
		bs:updBales(obj, farm, fillType , 1)		-- incr new filltype
	end
end
