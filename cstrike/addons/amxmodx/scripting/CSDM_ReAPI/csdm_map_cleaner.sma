#include <amxmodx>
#include <csdm>
#include <fakemeta>
#include <hamsandwich>


#define IsPlayer(%1)			(1 <= %1 <= MaxClients)

enum
{
	func_bomb_target	= 	(1<<0),
	info_bomb_target	=	(1<<1),
	func_hostage_rescue	= 	(1<<2),
	info_hostage_rescue	=	(1<<3),
	func_vip_safetyzone	=	(1<<4),
	info_vip_start		=	(1<<5),
	hostage_entity		=	(1<<6),
	monster_scientist	=	(1<<7),
	func_escapezone 	=	(1<<8),
	func_buyzone		=	(1<<9),
	armoury_entity		=	(1<<10),
	game_player_equip	=	(1<<11),
	player_weaponstrip	=	(1<<12)
}

new const g_szMapEntityList[][] =
{
	"func_bomb_target",
	"info_bomb_target",
	"func_hostage_rescue",
	"info_hostage_rescue",
	"func_vip_safetyzone",
	"info_vip_start",
	"hostage_entity",
	"monster_scientist",
	"func_escapezone",
	"func_buyzone",
	"armoury_entity",
	"game_player_equip",
	"player_weaponstrip"
}

new Trie:g_tMapEntitys, g_iFwdEntitySpawn, g_iFwdSetModel
new g_bitRemoveObjects, bool:g_bRemoveWeapons, bool:g_bExcludeBomb
new HamHook:g_hWeaponBoxSpawn, HamHook:g_hShieldSpawn

public plugin_precache()
{
	g_tMapEntitys = TrieCreate()

	for(new i = 0; i < sizeof(g_szMapEntityList); i++)
	{
		TrieSetCell(g_tMapEntitys, g_szMapEntityList[i], i)
	}

	g_iFwdEntitySpawn = register_forward(FM_Spawn, "Entity_Spawn")

	if(g_bitRemoveObjects & func_buyzone) {
		CreateBuyZone()
	}
}

public CSDM_Initialized(const szVersion[])
{
	if(!szVersion[0])
		pause("ad")
}

public CSDM_ConfigurationLoad(const ReadTypes:iReadAction)
{
	CSDM_RegisterConfig("mapcleaner", "ReadCfg")
}

public plugin_init()
{
	register_plugin("CSDM Map Cleaner", CSDM_VERSION, "wopox1337")

	if(g_iFwdEntitySpawn) {
		unregister_forward(FM_Spawn, g_iFwdEntitySpawn)
	}
	if(g_tMapEntitys) {
		TrieDestroy(g_tMapEntitys)
	}

	DisableHamForward(g_hWeaponBoxSpawn = RegisterHam(Ham_Spawn, "weaponbox", "CWeaponBox_Spawn", .Post = true))
	DisableHamForward(g_hShieldSpawn = RegisterHam(Ham_Spawn, "weapon_shield", "CWShield_Spawn", .Post = true))
}

public plugin_cfg()
{
	CheckForwards()
}

public CWShield_Spawn(const pShield)
{
	if(pShield > 0 && IsPlayer(get_entvar(pShield, var_owner))) {
		set_entvar(pShield, var_flags, FL_KILLME)
	}
}

public CWeaponBox_Spawn(const pWeaponBox)
{
	state SetModel_Enabled
}


public Entity_SetModel(const pEntity, const szModel[]) <SetModel_Enabled>
{
	state SetModel_Disabled

	if(!is_nullent(pEntity))
	{
		if(!g_bExcludeBomb && get_member(pEntity, m_WeaponBox_bIsBomb))
		{
			KillWeaponBoxBomb(pEntity)
			return FMRES_IGNORED
		}

		ENTITY_THINK(pEntity)
		// set_entvar(pEntity, var_nextthink, get_gametime() + 0.1)
	}

	return FMRES_IGNORED
}

public Entity_SetModel(const pEntity, const szModel[]) <SetModel_Disabled>
{
	return FMRES_IGNORED
}

public Entity_Spawn(const pEntity)
{
	if(is_nullent(pEntity))
		return FMRES_IGNORED

	static szClassName[32], bits
	get_entvar(pEntity, var_classname, szClassName, charsmax(szClassName))

	if(!TrieGetCell(g_tMapEntitys, szClassName, bits))
		return FMRES_IGNORED

	if(g_bitRemoveObjects & (1 << bits))
	{
		REMOVE_ENTITY(pEntity)
		return FMRES_SUPERCEDE
	}

	return FMRES_IGNORED
}

public ReadCfg(const szLineData[], const iSectionID)
{
	new szKey[MAX_KEY_LEN], szValue[MAX_VALUE_LEN], szSign[2]
	if(!ParseConfigKey(szLineData, szKey, szSign, szValue))
		return

	if(equali(szKey, "remove_objective_flags"))
	{
		if(ContainFlag(szValue, "a"))
			g_bitRemoveObjects |= (func_vip_safetyzone|info_vip_start|func_escapezone)
		if(ContainFlag(szValue, "b"))
			g_bitRemoveObjects |= func_buyzone
		if(ContainFlag(szValue, "c"))
			g_bitRemoveObjects |= (func_hostage_rescue|info_hostage_rescue|hostage_entity|monster_scientist)
		if(ContainFlag(szValue, "d"))
			g_bitRemoveObjects |= (func_bomb_target|info_bomb_target)
		if(ContainFlag(szValue, "e"))
			g_bitRemoveObjects |= (game_player_equip|player_weaponstrip)
		if(ContainFlag(szValue, "w"))
			g_bitRemoveObjects |= armoury_entity
	}
	else if(equali(szKey, "remove_dropped_weapons"))
	{
		g_bRemoveWeapons = bool:(str_to_num(szValue))
	}
	else if(equali(szKey, "exclude_bomb"))
	{
		g_bExcludeBomb = bool:(str_to_num(szValue))
	}
}

CheckForwards()
{
	if(g_bRemoveWeapons && !g_iFwdSetModel)
	{
		g_iFwdSetModel = register_forward(FM_SetModel, "Entity_SetModel", ._post = false)
		EnableHamForward(g_hWeaponBoxSpawn)
		EnableHamForward(g_hShieldSpawn)
	}
	else if(!g_bRemoveWeapons && g_iFwdSetModel)
	{
		unregister_forward(FM_SetModel, g_iFwdSetModel, .post = false)
		DisableHamForward(g_hWeaponBoxSpawn)
		DisableHamForward(g_hShieldSpawn)

		g_iFwdSetModel = 0
	}

	state SetModel_Disabled
}

CreateBuyZone()
{
	new pEntity = rg_create_entity("func_buyzone")
	if(!is_nullent(pEntity))
	{
		// SET_SIZE(pEntity, Vector(-1, -1, -1), Vector(1, 1, 1))
		// SET_ORIGIN(pEntity, VECTOR_ZERO)
		set_entvar(pEntity, var_solid, SOLID_NOT)
	}
}

stock KillWeaponBoxBomb(const pWeaponBox)
{
	new pWeapon = get_member(pWeaponBox, m_WeaponBox_rgpPlayerItems, C4_SLOT)
	if(!is_nullent(pWeapon)) {
		set_entvar(pWeapon, var_flags, FL_KILLME)
	}

	set_entvar(pWeaponBox, var_flags, FL_KILLME)

	static iMsgIdBombPickup
	if(iMsgIdBombPickup || (iMsgIdBombPickup = get_user_msgid("BombPickup")))
	{
		message_begin(MSG_ALL, iMsgIdBombPickup)
		message_end()
	}
}
