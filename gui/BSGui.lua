--=======================================================================================================
--  BALESEE HOTSPOT GUI
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

BSGui = {}
local BSGui_mt = Class(BSGui, YesNoDialog)

BSGui.CONTROLS = {          -- to address the different Gui elements by their id 
	"setShowBales",
	"setShowPals",
	"setSize",
	"setFarm",
	"setAll",
	"helpBox",
	"helpBoxText",
	"baleList",
	"palletList",
	"statsContainer",     
	"baletableHeaderBox",
	"paltableHeaderBox",
	"sumBal",
	"sumPal",
	"bcount",
	"pcount",
}
function BSGui.new(target, custom_mt)
	local self = YesNoDialog.new(target, custom_mt or BSGui_mt)
	self:registerControls(BSGui.CONTROLS)
	self.farmIds = {}
	return self
end
function BSGui:onGuiSetupFinished()
	BSGui:superClass().onGuiSetupFinished(self)
	self.baleList:setDataSource(self)
	self.palletList:setDataSource(self)
	-- set tooltip texts (std game doesn't find mod ign names)
	local tips = {
		"BS_tipShowBales",
		"BS_tipShowPals",
		"BS_tipSize",
		"BS_tipFarm",
		"BS_tipAll",
	}
	for i=1,5 do
		self[BSGui.CONTROLS[i]].toolTipText = g_i18n:getText(tips[i])
	end
end
function BSGui:getNumberOfSections(list)
	if list == self.baleList then
		return #self.bsections
	else
		return #self.psections
	end
end
function BSGui:getNumberOfItemsInSection(list, section)
	if list == self.baleList then
		return #self.bsections[section].btypes
	else
		return #self.psections[section].ptypes
	end
end
function BSGui:getTitleForSectionHeader(list, section)
	if list == self.baleList then
		return self.bsections[section].title
	else
		return self.psections[section].title
	end
end
function BSGui:populateCellForItemInSection(list, section, index, cell)
	local type
	if list == self.baleList then
		type = self.bsections[section].btypes[index]
	else
		type = self.psections[section].ptypes[index]
	end
	cell:getAttribute("btype"):setText(type.text)
	cell:getAttribute("count"):setText(type.number)
end
function BSGui:onOpen()
	-- check for new bales/ pallets, even if we don't display the hotspots
	BSGui:superClass().onOpen(self)
	local bs = BaleSee
	if bs.baleState == BS.OFF then bs:updateHotspots("bale") end
	if bs.palState == BS.OFF then bs:updateHotspots("pallet") end

	local farm = bs.statFarm
	if farm == nil then
		farm = g_currentMission:getFarmId()
	end
	self:sortList(farm)
	self.baleList:reloadData()   
	self.palletList:reloadData()   
	-- totals row:
	self.bcount:setText(tostring(bs.numBales[farm])) 
	self.sumBal:setVisible(bs.numBales[farm] > 0)
	self.pcount:setText(tostring(bs.numPals[farm])) 
	self.sumPal:setVisible(bs.numPals[farm] > 0)
end
function BSGui:sortList(farm)
	local bs = BaleSee
	-- distribute listitems to sections
	local function sortFunc(a, b)
		return a.text < b.text
	end
	-- bale list:
	self.bsections = {
		{title = bs.ROUND, btypes = {} },
		{title = bs.SQUARE,btypes = {} }
	}
	for hash,v in pairs(bs.bales[farm]) do
		if v.number > 0 then 
			if math.abs(hash) / 100000 > 1 then 
				table.insert(self.bsections[1].btypes, v)
			else
				table.insert(self.bsections[2].btypes, v)
			end
		end
	end
	for i=2,1,-1 do
		if #self.bsections[i].btypes > 0 then 
			table.sort(self.bsections[i].btypes, sortFunc)
		else
			table.remove(self.bsections, i)
		end
	end
	-- pallet list:
	self.psections = {
		{title = g_i18n:getText("BS_palSupplies"), ptypes = {} },
		{title = g_i18n:getText("BS_palFarm"), ptypes = {} },
		{title = g_i18n:getText("BS_palFood"), ptypes = {} },
		{title = g_i18n:getText("BS_palIndustry"), ptypes = {} }
	}
	local cat
	for ft,v in pairs(bs.pallets[farm]) do
		if bs.pallCols[ft] ~= nil then 
			cat = bs.pallCols[ft][3]
		end
		if cat == nil then 
			Logging.warning("%s: No category found for pallet fillType %d",
				bs.name, ft)
			cat = 1
		end
		if v > 0 then 
			table.insert(self.psections[cat].ptypes, 
				{text= g_fillTypeManager:getFillTypeTitleByIndex(ft), number= v})
		end
	end
	for i=4,1,-1 do
		if #self.psections[i].ptypes > 0 then 
			table.sort(self.psections[i].ptypes, sortFunc)
		else
			table.remove(self.psections, i)
		end
	end
end
function BSGui:onClickShowBales( ix )
	-- multiTextOption clicked
	local bs = BaleSee
	local oldState = bs.baleState
	bs.baleState = ix
	if bs.baleState ~= BS.OFF then 						-- dots true, if new baleState 3
		for i = 1,8 do
			bs:toggleCol(bs.bHotspots[i], bs.baleState == 3, false)
		end
	end
	if bs.isMultiplayer then 
		self.baleVisDirty = self.baleVisDirty or oldState == 1 or bs.baleState == 1
		-- handle later, on dialog close
	else 		-- single player
		if oldState == 1 or bs.baleState == 1 then 		-- switch display on / off
			bs:toggleVis(bs.bHotspots[1], oldState == 1)   -- switch on, if display was off
		end
	end
end
function BSGui:onClickShowPals( ix )
	local bs = BaleSee
	local oldState = bs.palState
	bs.palState = ix
	if oldState == 1 or bs.palState == 1 then 
		bs:toggleVis(bs.pHotspots, oldState == 1) 
	end
	if bs.palState ~= 1 then
		bs:toggleCol(bs.pHotspots, bs.palState == 3, true)
	end
end
function BSGui:onClickSize( ix )
	BaleSee.dispSize = ix
	BaleSee:toggleSize(ix)
end
function BSGui:onClickAll( ix )
	BaleSee.showAll = ix == 1
	self.showDirty = true
end
function BSGui:onClickFarm( ix )
	local bs = BaleSee
	-- convert to farmId
	farmId = self.farmIds[ix]
	bs.statFarm = farmId
	self:sortList(farmId)
	self.baleList:reloadData()   
	self.palletList:reloadData()   
	-- totals row:
	self.bcount:setText(tostring(bs.numBales[farmId])) 
	self.sumBal:setVisible(bs.numBales[farmId] > 0)
	self.pcount:setText(tostring(bs.numPals[farmId])) 
	self.sumPal:setVisible(bs.numPals[farmId] > 0)
end
function BSGui:onToolTipBoxTextChanged(toolTipBox)
	local showText = (toolTipBox.text ~= nil and toolTipBox.text ~= "")
	self.helpBox:setVisible(showText)
end
function BSGui:onClickBack(forceBack, usedMenuButton)
	local bs = BaleSee
	if bs.isMultiplayer then
		local farm = g_currentMission:getFarmId()
		if self.baleVisDirty then 	-- there were clicks on showBales
			self.baleVisDirty = false 
			if bs.baleState == BS.OFF then 	-- switch off all farms bales
				for i=1,8 do
					bs:toggleVis(bs.bHotspots[i], false)
				end
			elseif bs.showAll then  		-- switch on all farms bales
				for i=1,8 do
					bs:toggleVis(bs.bHotspots[i], true)
				end
			else 							-- switch on my farms bales
				bs:toggleVis(bs.bHotspots[farm], true)
			end
		elseif self.showDirty then 	-- there were clicks on showAll
			self.showDirty = false
			if bs.baleState > BS.OFF then 	-- bales are visible
				for i=1,8 do
					bs:toggleVis(bs.bHotspots[i], bs.showAll)
				end
				if not bs.showAll then 		-- switch on my farms bales
					bs:toggleVis(bs.bHotspots[farm], true)
				end
			end
		end
	end	
	self:close()
end
