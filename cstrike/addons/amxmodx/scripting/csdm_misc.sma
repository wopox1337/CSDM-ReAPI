#include <amxmodx>
#include <hamsandwich>
#include <csdm>


#define IsPlayer(%1)				(1 <= (%1) <= g_iMaxPlayers)

const HideWeapon_Flags = 1 	// "HideWeapon" msg argument

new const g_szWeaponList[][] =
{
	"weapon_m4a1",
	"weapon_usp",
	"weapon_famas",
	"weapon_glock18"
}

new HamHook:g_hSecondaryAttack[sizeof(g_szWeaponList)], HamHook:g_hAddToPlayer[sizeof(g_szWeaponList)]

new g_bWeaponState[MAX_CLIENTS + 1][CSW_P90 + 1]
new g_iMaxPlayers

new bool:g_bWeaponStateRemember = true, g_bitHideHudFlags, g_iRefillClip = 1


public plugin_init()
{
	register_plugin("CSDM Misc", CSDM_VERSION, "wopox1337")

	for(new i = 0; i < sizeof(g_szWeaponList); i++)
	{
		DisableHamForward(g_hAddToPlayer[i] = RegisterHam(Ham_Item_AddToPlayer, g_szWeaponList[i], "CBasePlayerItem_AddToPlayer", .Post = true))
		DisableHamForward(g_hSecondaryAttack[i] = RegisterHam(Ham_Weapon_SecondaryAttack, g_szWeaponList[i], "CBasePlayerItem_SecAttack", .Post = true))
	}

	g_iMaxPlayers = get_maxplayers()
}

public plugin_cfg()
{
	CheckForwards()
}

public client_putinserver(pPlayer)
{
	g_bWeaponState[pPlayer][CSW_M4A1] = g_bWeaponState[pPlayer][CSW_USP] = g_bWeaponState[pPlayer][CSW_FAMAS] = g_bWeaponState[pPlayer][CSW_GLOCK18] = 0;
}


public CSDM_Initialized(const szVersion[])
{
	if(!szVersion[0])
		pause("ad")
}

public CSDM_ConfigurationLoad(const ReadTypes:iReadAction)
{
	CSDM_RegisterConfig("misc", "ReadCfg")
}

public CSDM_PlayerKilled(const pVictim, const pKiller, const HitBoxGroup:iLastHitGroup)
{
	if(!g_iRefillClip || !pKiller)
		return

	if(pVictim != pKiller && is_user_alive(pKiller))
	{
		switch(g_iRefillClip)
		{
			case 1:
			{
				new pActiveWeapon = get_member(pKiller, m_pActiveItem)
				if(!is_nullent(pActiveWeapon)) {
					rg_instant_reload_weapons(pKiller, pActiveWeapon)
				}
			}
			case 2:	rg_instant_reload_weapons(pKiller) // all
		}
	}
}

public CBasePlayerItem_SecAttack(const pWeapon)
{
	if(pWeapon <= 0)
		return HAM_IGNORED

	new pPlayer = get_member(pWeapon, m_pPlayer)
	if(IsPlayer(pPlayer)) {
		g_bWeaponState[pPlayer][get_member(pWeapon, m_iId)] = get_member(pWeapon, m_Weapon_iWeaponState)
	}

	return HAM_IGNORED
}

public CBasePlayerItem_AddToPlayer(const pWeapon, const pPlayer)
{
	if(pWeapon > 0 && IsPlayer(pPlayer)) {
		set_member(pWeapon, m_Weapon_iWeaponState, g_bWeaponState[pPlayer][get_member(pWeapon, m_iId)])
	}

	return HAM_IGNORED
}

public Message_HideWeapon(const iMsgId, const iMsgDest, const iMsgEntity)
{
	if(g_bitHideHudFlags) {
		set_msg_arg_int(HideWeapon_Flags, ARG_BYTE, get_msg_arg_int(HideWeapon_Flags) | g_bitHideHudFlags)
	}
}

public ReadCfg(const szLineData[], const iSectionID)
{
	new szKey[MAX_KEY_LEN], szValue[MAX_VALUE_LEN], szSign[2]
	if(!ParseConfigKey(szLineData, szKey, szSign, szValue))
		return

	if(equali(szKey, "weaponstate_remember"))
	{
		g_bWeaponStateRemember = bool:(str_to_num(szValue))
	}
	else if(equali(szKey, "refill_clip_weapons"))
	{
		g_iRefillClip = clamp(str_to_num(szValue), 0, 2)
	}
	else if(equali(szKey, "hide_hud_flags"))
	{
		if(ContainFlag(szValue, "c"))
			g_bitHideHudFlags |= HIDEHUD_CROSSHAIR
		if(ContainFlag(szValue, "f"))
			g_bitHideHudFlags |= HIDEHUD_FLASHLIGHT
		if(ContainFlag(szValue, "m"))
			g_bitHideHudFlags |= HIDEHUD_MONEY
		if(ContainFlag(szValue, "h"))
			g_bitHideHudFlags |= HIDEHUD_HEALTH
		if(ContainFlag(szValue, "t"))
			g_bitHideHudFlags |= HIDEHUD_TIMER
	}
}

CheckForwards()
{
	static iMsgIdHideWeapon, iMsgHookHideWeapon
	if(!iMsgIdHideWeapon) {
		iMsgIdHideWeapon = get_user_msgid("HideWeapon")
	}

	for(new i = 0; i < sizeof(g_szWeaponList); i++)
	{
		if(g_bWeaponStateRemember)
		{
			EnableHamForward(g_hAddToPlayer[i])
			EnableHamForward(g_hSecondaryAttack[i])
		}
		else
		{
			DisableHamForward(g_hAddToPlayer[i])
			DisableHamForward(g_hSecondaryAttack[i])
		}
	}

	if(g_bitHideHudFlags && !iMsgHookHideWeapon)
	{
		iMsgHookHideWeapon = register_message(iMsgIdHideWeapon, "Message_HideWeapon")
	}
	else if(!g_bitHideHudFlags && iMsgHookHideWeapon)
	{
		unregister_message(iMsgIdHideWeapon, iMsgHookHideWeapon)
		iMsgHookHideWeapon = 0
	}
}



