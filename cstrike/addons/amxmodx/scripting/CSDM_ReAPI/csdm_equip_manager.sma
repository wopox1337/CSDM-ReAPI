new const g_szEquipMenuCmds[][] =
{
	"say /guns",
	"say guns",
	"say_team /guns",
	"say_team guns",

	"csdm_guns",
	"csdm_equipmenu",

	"cl_autobuy"
}

#include <amxmodx>
#include <csdm>
#include <fakemeta>


#define IsPlayerNotUsed(%1)		(g_iPreviousSecondary[%1] == INVALID_INDEX && g_iPreviousPrimary[%1] == INVALID_INDEX)
#define UserHasPrim(%1)			(get_member(%1, m_rgpPlayerItems, PRIMARY_WEAPON_SLOT) > 0 || get_member(%1, m_bHasPrimary))
#define UserHasSec(%1)			(get_member(%1, m_rgpPlayerItems, PISTOL_SLOT) > 0)


const CSDM_BUYZONE_KEY	= 71952486

enum equip_data_s
{
	szWeaponName[20],
	szDisplayName[32],
	iAmount,
	TeamName:iTeam,
	WeaponIdType:iWeaponID
}

enum arraylist_e
{
	Array:Autoitems,
	Array:Primary,
	Array:Secondary,
	Array:BotSecondary,
	Array:BotPrimary
}

enum
{
	BUYZONE_REMOVE,
	BUYZONE_TRIGGER_ON,
	BUYZONE_TRIGGER_OFF
}

enum EquipMenu_s
{
	em_newWeapons,
	em_previous,
	em_dontShowAgain,
	em_random,
	em_always_random
}

new HookChain:g_hGiveDefaultItems, HookChain:g_hBuyWeaponByWeaponID, HookChain:g_hHasRestrictItem
new Array:g_aArrays[arraylist_e], Trie:g_tCheckItemName
new g_iPreviousSecondary[MAX_CLIENTS + 1], g_iPreviousPrimary[MAX_CLIENTS + 1], bool:g_bOpenMenu[MAX_CLIENTS + 1], bool:g_bAlwaysRandom[MAX_CLIENTS + 1]
new Float:g_flPlayerBuyTime[MAX_CLIENTS + 1]

new g_iSecondarySection, g_iPrimarySection, g_iBotSecondarySection, g_iBotPrimarySection
new g_iNumPrimary, g_iNumSecondary, g_iNumBotPrimary, g_iNumBotSecondary, g_iNumAutoItems

new EquipTypes:g_iEquipMode = EQUIP_MENU, bool:g_bBlockDefaultItems = true
new bool:g_bAlwaysOpenMenu, Float:g_flFreeBuyTime, g_iFreeBuyMoney
new bool:g_bHasMapParameters, mp_maxmoney


public plugin_init()
{
	register_plugin("CSDM Equip Manager", CSDM_VERSION, "wopox1337")
	register_dictionary("csdm_reapi.txt")
	register_dictionary("common.txt")

	for(new i = 0; i < sizeof(g_szEquipMenuCmds); i++)
	{
		register_clcmd(g_szEquipMenuCmds[i], "ClCmd_EnableMenu")
	}

	DisableHookChain(g_hGiveDefaultItems = RegisterHookChain(RG_CBasePlayer_GiveDefaultItems, "CBasePlayer_GiveDefaultItems", .post = false))
	DisableHookChain(g_hBuyWeaponByWeaponID = RegisterHookChain(RG_BuyWeaponByWeaponID, "BuyWeaponByWeaponID", .post = true))
	DisableHookChain(g_hHasRestrictItem = RegisterHookChain(RG_CBasePlayer_HasRestrictItem, "CBasePlayer_HasRestrictItem", .post = false))

	g_bHasMapParameters = bool:rg_find_ent_by_class(NULLENT, "info_map_parameters")
	mp_maxmoney = get_cvar_pointer("mp_maxmoney")
}

public CSDM_Initialized(const szVersion[])
{
	if(!szVersion[0])
		pause("ad")
}

public plugin_cfg()
{
	CheckForwards()
}

public plugin_end()
{
	ArrayDestroy(g_aArrays[Autoitems])
	ArrayDestroy(g_aArrays[Secondary])
	ArrayDestroy(g_aArrays[Primary])
	ArrayDestroy(g_aArrays[BotSecondary])
	ArrayDestroy(g_aArrays[BotPrimary])

	TrieDestroy(g_tCheckItemName)
}

// API
public EquipTypes:get_equip_mode()
{
	return g_iEquipMode
}

public set_equip_mode(const iNewEquipmode)
{
	g_iEquipMode = EquipTypes:clamp(iNewEquipmode, _:AUTO_EQUIP, _:FREE_BUY)
	CheckForwards()
}


public CSDM_ConfigurationLoad(const ReadTypes:iReadAction)
{
	if(!g_tCheckItemName)
	{
		g_tCheckItemName = TrieCreate()
		for(new iId = 0; iId < sizeof(g_szValidItemNames); iId++)
		{
			TrieSetCell(g_tCheckItemName, g_szValidItemNames[iId], g_szValidItemNames[iId][0] ? iId : 0) // WEAPON_NONE
		}
	}

	g_aArrays[Autoitems] = ArrayCreate(equip_data_s)
	g_aArrays[Secondary] = ArrayCreate(equip_data_s)
	g_aArrays[Primary] = ArrayCreate(equip_data_s)
	g_aArrays[BotSecondary] = ArrayCreate(equip_data_s)
	g_aArrays[BotPrimary] = ArrayCreate(equip_data_s)

	CSDM_RegisterConfig("equip", "ReadCfg_Settings")
	CSDM_RegisterConfig("autoitems", "ReadCfg_AutoItems")
	g_iSecondarySection = CSDM_RegisterConfig("secondary", "ReadCfg_MenuItems")
	g_iPrimarySection = CSDM_RegisterConfig("primary", "ReadCfg_MenuItems")
	g_iBotSecondarySection = CSDM_RegisterConfig("botsecondary", "ReadCfg_BotWeapons")
	g_iBotPrimarySection = CSDM_RegisterConfig("botprimary", "ReadCfg_BotWeapons")
}

public CSDM_ExecuteCVarValues()
{
	if(g_iEquipMode == FREE_BUY)
	{
		set_cvar_num("mp_buytime", -1)

		if(g_iFreeBuyMoney > 0) {
			set_cvar_num("mp_startmoney", g_iFreeBuyMoney)
		}
	}
}

public CSDM_RestartRound(const bool:bNewGame)
{
	if(!bNewGame || !g_bBlockDefaultItems)
		return

	new iPlayers[32], iCount, pPlayer

	get_players(iPlayers, iCount, "ah")
	for(--iCount; iCount >= 0; iCount--)
	{
		pPlayer = iPlayers[iCount]
		if(get_member(pPlayer, m_bNotKilled)) {
			rg_remove_all_items(pPlayer)
		}
	}
}

public client_putinserver(pPlayer)
{
	g_iPreviousSecondary[pPlayer] = g_iPreviousPrimary[pPlayer] = INVALID_INDEX
	g_bOpenMenu[pPlayer] = true
	g_bAlwaysRandom[pPlayer] = false
	g_flPlayerBuyTime[pPlayer] = 0.0
}

public ClCmd_EnableMenu(const pPlayer)
{
	if(g_iEquipMode != EQUIP_MENU)
		return PLUGIN_HANDLED

	if((is_user_alive(pPlayer) && IsPlayerNotUsed(pPlayer)) || g_bAlwaysOpenMenu) {
		MenuShow_EquipMenu(pPlayer)
		return PLUGIN_HANDLED
	}

	client_print_color(pPlayer, print_team_blue, "^4[CSDM] %L", pPlayer, "MENU_WILL_BE_OPENED")
	g_bOpenMenu[pPlayer] = true
	g_bAlwaysRandom[pPlayer] = false

	return PLUGIN_HANDLED
}

public CSDM_PlayerSpawned(const pPlayer, const bool:bIsBot, const iNumSpawns)
{
	if(g_iEquipMode == FREE_BUY)
	{
		if(g_bBlockDefaultItems || !user_has_weapon(pPlayer, CSW_KNIFE)) {
			rg_give_item(pPlayer, "weapon_knife")
		}

		if(g_flFreeBuyTime > 0.0) {
			g_flPlayerBuyTime[pPlayer] = get_gametime() + g_flFreeBuyTime
		}

		rg_add_account(pPlayer, g_iFreeBuyMoney > 0 ? g_iFreeBuyMoney : get_pcvar_num(mp_maxmoney), AS_SET)
		return
	}

	GiveAutoItems(pPlayer)

	if(g_iEquipMode == AUTO_EQUIP)  // only autoitems ?
		return

	if(bIsBot)
	{
		RandomWeapons(pPlayer, g_aArrays[BotSecondary], g_iNumBotSecondary)
		RandomWeapons(pPlayer, g_aArrays[BotPrimary], g_iNumBotPrimary)
		return
	}

	if(g_iEquipMode == EQUIP_MENU)
	{
		if(g_bOpenMenu[pPlayer])
		{
			MenuShow_EquipMenu(pPlayer)
		}
		
		if(!g_bAlwaysRandom[pPlayer])
		{
			PreviousWeapons(pPlayer, g_aArrays[Secondary], g_iPreviousSecondary[pPlayer])
			PreviousWeapons(pPlayer, g_aArrays[Primary], g_iPreviousPrimary[pPlayer])
		}
		else
		{
			RandomWeapons(pPlayer, g_aArrays[Secondary], g_iNumSecondary)
			RandomWeapons(pPlayer, g_aArrays[Primary], g_iNumPrimary)
		}
	}
	else if(g_iEquipMode == RANDOM_WEAPONS)
	{
		RandomWeapons(pPlayer, g_aArrays[Secondary], g_iNumSecondary)
		RandomWeapons(pPlayer, g_aArrays[Primary], g_iNumPrimary)
	}
}

// CBasePlayer
public CBasePlayer_GiveDefaultItems(const pPlayer)
{
	return HC_SUPERCEDE
}

public CBasePlayer_HasRestrictItem(const pPlayer, const ItemID:iItemId, const ItemRestType:iRestType)
{
	if(iItemId == ITEM_NONE || iRestType != ITEM_TYPE_BUYING)
		return HC_CONTINUE

	if(g_flFreeBuyTime > 0.0 && g_flPlayerBuyTime[pPlayer] < get_gametime())
	{
		client_print(pPlayer, print_center, "%L", pPlayer, "FREEBUYTIME_PASSED", g_flFreeBuyTime)
		SetHookChainReturn(ATYPE_BOOL, true)
		return HC_SUPERCEDE
	}

	return HC_CONTINUE
}

public BuyWeaponByWeaponID(const pPlayer, const WeaponIdType:weaponID)
{
	if(GetHookChainReturn(ATYPE_INTEGER) > 0 && IsValidWeaponID(weaponID) && g_iMaxBPAmmo[weaponID] > 0) {
		rg_set_user_bpammo(pPlayer, weaponID, g_iMaxBPAmmo[weaponID])
	}

	return HC_CONTINUE
}

// Menus
MenuShow_EquipMenu(const pPlayer) {
	if(!is_user_connected(pPlayer))
		return PLUGIN_HANDLED

	new menu = menu_create(fmt("%L", pPlayer, "EQUIP_MENU"), "MenuHandler_EquipMenu")

	static callback
	if(!callback)
		callback = menu_makecallback("MenuCallback_EquipMenu")

	menu_additem(menu, fmt("%L", pPlayer, "NEW_WEAPONS"), .callback = callback)
	menu_additem(menu, fmt("%L", pPlayer, "PREVIOUS_SETUP"), .callback = callback)
	menu_additem(menu, fmt("%L", pPlayer, "DONT_SHOW_MENU_AGAIN"), .callback = callback)
	menu_additem(menu, fmt("%L", pPlayer, "RANDOM_SELECTION"), .callback = callback)
	menu_additem(menu, fmt("%L", pPlayer, "ALWAYS_RANDOM"), .callback = callback)

	if(g_iNumSecondary || g_iNumPrimary)
		menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER)

	menu_setprop(menu, MPROP_NUMBER_COLOR, "\y")

	menu_display(pPlayer, menu)
	return PLUGIN_HANDLED
}

public MenuCallback_EquipMenu(const pPlayer, const menu, const EquipMenu_s:item) {
	if(!g_iNumSecondary && !g_iNumPrimary)
		return ITEM_DISABLED

	if((item == em_previous || item == em_dontShowAgain) && IsPlayerNotUsed(pPlayer))
		return ITEM_DISABLED

	return ITEM_IGNORE
}

public MenuHandler_EquipMenu(const pPlayer, const menu, const item) {
	menu_destroy(menu)

	if(item < 0)
		return PLUGIN_HANDLED

	switch(item) {
		case em_newWeapons: {
			g_iNumSecondary ? MenuShow_SecondaryWeapons(pPlayer) : MenuShow_PrimaryWeapons(pPlayer)
		}
		case em_previous: {
			PreviousWeapons(pPlayer, g_aArrays[Secondary], g_iPreviousSecondary[pPlayer])
			PreviousWeapons(pPlayer, g_aArrays[Primary], g_iPreviousPrimary[pPlayer])
		}
		case em_dontShowAgain: {
			PreviousWeapons(pPlayer, g_aArrays[Secondary], g_iPreviousSecondary[pPlayer])
			PreviousWeapons(pPlayer, g_aArrays[Primary], g_iPreviousPrimary[pPlayer])

			client_print_color(pPlayer, print_team_grey, "^4[CSDM] %L", pPlayer, "CHAT_HELP_GUNS")
			g_bOpenMenu[pPlayer] = false
		}
		case em_random: {
			g_iPreviousSecondary[pPlayer] = RandomWeapons(pPlayer, g_aArrays[Secondary], g_iNumSecondary)
			g_iPreviousPrimary[pPlayer] = RandomWeapons(pPlayer, g_aArrays[Primary], g_iNumPrimary)
		}
		case em_always_random: {
			g_iPreviousSecondary[pPlayer] = RandomWeapons(pPlayer, g_aArrays[Secondary], g_iNumSecondary)
			g_iPreviousPrimary[pPlayer] = RandomWeapons(pPlayer, g_aArrays[Primary], g_iNumPrimary)

			client_print_color(pPlayer, print_team_grey, "^4[CSDM] %L", pPlayer, "CHAT_HELP_GUNS")
			g_bOpenMenu[pPlayer] = false
			g_bAlwaysRandom[pPlayer] = true
		}		
	}

	return PLUGIN_HANDLED
}

MenuShow_PrimaryWeapons(const pPlayer) {
	if(!is_user_connected(pPlayer))
		return;

	new menu = menu_create(fmt("%L", pPlayer, "PRIMARY_WEAPONS"), "MenuHandler_PrimaryWeapons")

	AddItemsToMenu(menu, g_aArrays[Primary], g_iNumPrimary)

	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER)
	menu_setprop(menu, MPROP_NUMBER_COLOR, "\y")

	menu_display(pPlayer, menu)
}

public MenuHandler_PrimaryWeapons(const pPlayer, const menu, const item) {
	menu_destroy(menu)

	if(item < 0)
		return PLUGIN_HANDLED

	new eWeaponData[equip_data_s]
	ArrayGetArray(g_aArrays[Primary], item, eWeaponData)

	GiveWeapon(pPlayer, eWeaponData)
	g_iPreviousPrimary[pPlayer] = item

	return PLUGIN_HANDLED
}

MenuShow_SecondaryWeapons(const pPlayer) {
	if(!is_user_connected(pPlayer))
		return;

	new menu = menu_create(fmt("%L", pPlayer, "SECONDARY_WEAPONS"), "MenuHandler_SecondaryWeapons")

	AddItemsToMenu(menu, g_aArrays[Secondary], g_iNumSecondary)

	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER)
	menu_setprop(menu, MPROP_NUMBER_COLOR, "\y")

	menu_display(pPlayer, menu)
}

public MenuHandler_SecondaryWeapons(const pPlayer, const menu, const item) {
	menu_destroy(menu)

	if(item < 0)
		return PLUGIN_HANDLED

	new eWeaponData[equip_data_s]
	ArrayGetArray(g_aArrays[Secondary], item, eWeaponData)

	GiveWeapon(pPlayer, eWeaponData)
	g_iPreviousSecondary[pPlayer] = item

	MenuShow_PrimaryWeapons(pPlayer)

	return PLUGIN_HANDLED
}

// Config callbacks
public ReadCfg_Settings(const szLineData[], const iSectionID)
{
	new szKey[MAX_KEY_LEN], szValue[MAX_VALUE_LEN], szSign[2]
	if(ParseConfigKey(szLineData, szKey, szSign, szValue))
	{
		if(equali(szKey, "equip_mode"))
		{
			g_iEquipMode = EquipTypes:clamp(str_to_num(szValue), _:AUTO_EQUIP, _:FREE_BUY)
		}
		else if(equali(szKey, "freebuy_time"))
		{
			g_flFreeBuyTime = floatmax(0.0, str_to_float(szValue))
		}
		else if(equali(szKey, "freebuy_money"))
		{
			g_iFreeBuyMoney = max(0, str_to_num(szValue))
		}
		else if(equali(szKey, "always_open_menu"))
		{
			g_bAlwaysOpenMenu = bool:(str_to_num(szValue))
		}
		else if(equali(szKey, "block_default_items"))
		{
			g_bBlockDefaultItems = bool:(str_to_num(szValue))
		}
	}
}

public ReadCfg_AutoItems(const szLineData[], const iSectionID)
{
	new szClassName[20], szTeam[4], szAmount[4], eWeaponData[equip_data_s]
	if(parse(szLineData, szClassName, charsmax(szClassName), szTeam, charsmax(szTeam), szAmount, charsmax(szAmount)) != 3)
		return

	strtolower(szClassName)
	if(!(eWeaponData[iWeaponID] = _:GetWeaponIndex(szClassName)))
		return

	copy(eWeaponData[szWeaponName], charsmax(eWeaponData[szWeaponName]), szClassName)
	eWeaponData[iTeam] = _:(szTeam[0] == 't' ? TEAM_TERRORIST : szTeam[0] == 'c' ? TEAM_CT : TEAM_UNASSIGNED)
	eWeaponData[iAmount] = str_to_num(szAmount)

	ArrayPushArray(g_aArrays[Autoitems], eWeaponData)
	g_iNumAutoItems++
}

public ReadCfg_BotWeapons(szLineData[], const iSectionID)
{
	new eWeaponData[equip_data_s]

	strtolower(szLineData)
	if(!(eWeaponData[iWeaponID] = _:GetWeaponIndex(szLineData)))
		return

	copy(eWeaponData[szWeaponName], charsmax(eWeaponData[szWeaponName]), szLineData)

	if(iSectionID == g_iBotSecondarySection)
	{
		ArrayPushArray(g_aArrays[BotSecondary], eWeaponData)
		g_iNumBotSecondary++
	}
	else if(iSectionID == g_iBotPrimarySection)
	{
		ArrayPushArray(g_aArrays[BotPrimary], eWeaponData)
		g_iNumBotPrimary++
	}
}

public ReadCfg_MenuItems(const szLineData[], const iSectionID)
{
	new szClassName[20], szMenuText[32], eWeaponData[equip_data_s]
	if(parse(szLineData, szClassName, charsmax(szClassName), szMenuText, charsmax(szMenuText)) != 2)
		return

	strtolower(szClassName)
	if(!(eWeaponData[iWeaponID] = _:GetWeaponIndex(szClassName)))
		return

	copy(eWeaponData[szWeaponName], charsmax(eWeaponData[szWeaponName]), szClassName)
	copy(eWeaponData[szDisplayName], charsmax(eWeaponData[szDisplayName]), szMenuText)

	if(iSectionID == g_iSecondarySection)
	{
		ArrayPushArray(g_aArrays[Secondary], eWeaponData)
		g_iNumSecondary++
	}
	else if(iSectionID == g_iPrimarySection)
	{
		ArrayPushArray(g_aArrays[Primary], eWeaponData)
		g_iNumPrimary++
	}
}

// Functions
PreviousWeapons(const pPlayer, const Array:aArrayName, const iItemIndex)
{
	if(iItemIndex != INVALID_INDEX)
	{
		new eWeaponData[equip_data_s]
		ArrayGetArray(aArrayName, iItemIndex, eWeaponData)
		GiveWeapon(pPlayer, eWeaponData)
	}
}

RandomWeapons(const pPlayer, const Array:aArrayName, const iArraySize)
{
	if(!iArraySize)
		return INVALID_INDEX

	new eWeaponData[equip_data_s], iRand = random(iArraySize)
	ArrayGetArray(aArrayName, iRand, eWeaponData)
	GiveWeapon(pPlayer, eWeaponData)
	return iRand
}

GiveAutoItems(const pPlayer)
{
	if(!g_iNumAutoItems)
		return

	new eWeaponData[equip_data_s], i, TeamName:iPlayerTeam = get_member(pPlayer, m_iTeam)
	for(i = 0; i < g_iNumAutoItems; i++)
	{
		ArrayGetArray(g_aArrays[Autoitems], i, eWeaponData)
		if(iPlayerTeam == eWeaponData[iTeam] || eWeaponData[iTeam] == TEAM_UNASSIGNED) {
			GiveWeapon(pPlayer, eWeaponData)
		}
	}
}

GiveWeapon(const pPlayer, eData[equip_data_s])
{
	if(!is_user_alive(pPlayer))
		return;

	new WeaponIdType:iId = eData[iWeaponID]
	rg_give_item(pPlayer, eData[szWeaponName], (GRENADE_BS & (1 << any:iId)) ? GT_APPEND : GT_REPLACE)

	if(eData[iAmount] && eData[szWeaponName][0] == 'i' && (eData[szWeaponName][5] == 'a' || eData[szWeaponName][5] == 'k'))
	{
		set_entvar(pPlayer, var_armorvalue, float(eData[iAmount]))
	}
	else if(IsValidWeaponID(iId) && g_iMaxBPAmmo[iId] > 0)
	{
		rg_set_user_bpammo(pPlayer, iId, eData[iAmount] ? eData[iAmount] : g_iMaxBPAmmo[iId])
	}
}

WeaponIdType:GetWeaponIndex(const szClassName[])
{
	new WeaponIdType:iId = WEAPON_NONE
	if(!szClassName[0] || !TrieGetCell(g_tCheckItemName, szClassName, iId))
	{
		server_print("[CSDM] WARNING: Invalid item name ^"%s^" will be skipped!", szClassName)
		return WEAPON_NONE
	}

	return iId
}

AddItemsToMenu(const menu, const Array:array, const arraySize) {
	if(!arraySize)
		return

	new eWeaponData[equip_data_s]
	for(new i = 0; i < arraySize; i++)	{
		ArrayGetArray(array, i, eWeaponData)
		menu_additem(menu, eWeaponData[szDisplayName])
	}
}

CheckForwards()
{
	if(g_bBlockDefaultItems)
		EnableHookChain(g_hGiveDefaultItems)
	else
		DisableHookChain(g_hGiveDefaultItems)

	if(g_iEquipMode == FREE_BUY)
	{
		EnableHookChain(g_hBuyWeaponByWeaponID)
		if(g_flFreeBuyTime > 0.0)
			EnableHookChain(g_hHasRestrictItem)
		else
			DisableHookChain(g_hHasRestrictItem)

		if(!SetStateBuyZone(BUYZONE_TRIGGER_ON)) {
			CreateBuyZone()
		}
		if(g_bHasMapParameters)
		{
			set_member_game(m_bCTCantBuy, false)
			set_member_game(m_bTCantBuy, false)
		}
	}
	else
	{
		DisableHookChain(g_hBuyWeaponByWeaponID)
		DisableHookChain(g_hHasRestrictItem)

		SetStateBuyZone(BUYZONE_TRIGGER_OFF)
		if(g_bHasMapParameters)
		{
			set_member_game(m_bCTCantBuy, true)
			set_member_game(m_bTCantBuy, true)
		}
	}
}

CreateBuyZone()
{
	new pEntity = rg_create_entity("func_buyzone")
	SPAWN_ENTITY(pEntity)

	if(!is_nullent(pEntity))
	{
		SET_SIZE(pEntity, Vector(-8191, -8191, -8191), Vector(8191, 8191, 8191))
		SET_ORIGIN(pEntity, VECTOR_ZERO)
		SetEntityKeyID(pEntity, CSDM_BUYZONE_KEY)
		return pEntity
	}

	return NULLENT
}

bool:SetStateBuyZone(const iAction)
{
	new pEntity = NULLENT
	while((pEntity = rg_find_ent_by_class(pEntity, "func_buyzone")))
	{
		if(GetEntityKeyID(pEntity) != CSDM_BUYZONE_KEY)
			continue

		switch(iAction)
		{
			case BUYZONE_REMOVE: REMOVE_ENTITY(pEntity)
			case BUYZONE_TRIGGER_ON: set_entvar(pEntity, var_solid, SOLID_TRIGGER)
			case BUYZONE_TRIGGER_OFF: set_entvar(pEntity, var_solid, SOLID_NOT)
		}

		return true
	}

	return false
}
