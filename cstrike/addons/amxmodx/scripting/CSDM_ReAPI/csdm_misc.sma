#include <amxmodx>
#include <hamsandwich>
#include <csdm>
#include <reapi>

#define IsPlayer(%1)				(1 <= (%1) <= MaxClients)

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

new bool:g_bWeaponStateRemember = true, g_bitHideHudFlags, g_iRefillClip = 1, bool:g_bAllowResetScore = true

new bool: csdm_spec_menu_always
new bool: csdm_unlimited_team_changes

#define register_trigger_clcmd(%0,%1) \
	for (new iter = 0; iter < sizeof(BASE_CHAT_TRIGGERS); iter++) \
	{ \
		register_clcmd(fmt("say %s%s", BASE_CHAT_TRIGGERS[iter], %0), %1); \
		register_clcmd(fmt("say_team %s%s", BASE_CHAT_TRIGGERS[iter], %0), %1); \
	}

new stock const BASE_CHAT_TRIGGERS[][] = { "/", "\", "!", "." };

enum forwardlist_e
{
	iFwdPlayerResetScore
}

new g_eCustomForwards[forwardlist_e]

public plugin_init()
{
	register_plugin("CSDM Misc", CSDM_VERSION, "wopox1337")

	for(new i = 0; i < sizeof(g_szWeaponList); i++)
	{
		DisableHamForward(g_hAddToPlayer[i] = RegisterHam(Ham_Item_AddToPlayer, g_szWeaponList[i], "CBasePlayerItem_AddToPlayer", .Post = true))
		DisableHamForward(g_hSecondaryAttack[i] = RegisterHam(Ham_Weapon_SecondaryAttack, g_szWeaponList[i], "CBasePlayerItem_SecAttack", .Post = true))
	}

	RegisterHookChain(RG_HandleMenu_ChooseTeam, "HandleMenu_ChooseTeam_Pre", .post = false)
	RegisterHookChain(RG_HandleMenu_ChooseTeam, "HandleMenu_ChooseTeam", .post = true)
	RegisterHookChain(RG_ShowVGUIMenu, "ShowVGUIMenu_Pre", .post = false)

	new const CMDS_ResetScore[][] = { "rs", "resetscore" };
	for(new i; i < sizeof(CMDS_ResetScore); i++) {
		register_trigger_clcmd(CMDS_ResetScore[i], "hCMD_ResetScore")
	}

	g_eCustomForwards[iFwdPlayerResetScore] = CreateMultiForward("CSDM_PlayerResetScore", ET_IGNORE, FP_CELL)
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

public HandleMenu_ChooseTeam_Pre(const index, const MenuChooseTeam:slot)
{
	set_member(index, m_bForceShowMenu, true)

	if(csdm_spec_menu_always)
		set_member_game(m_bFreezePeriod, true)
}

public HandleMenu_ChooseTeam(const index, const MenuChooseTeam:slot)
{
	if(csdm_spec_menu_always)
		set_member_game(m_bFreezePeriod, false)

	if(csdm_unlimited_team_changes)
		set_member(index, m_bTeamChanged, false)

	if(get_member(index, m_iTeam) != TEAM_SPECTATOR)
		RequestFrame("SelectRandomAppearance", get_user_userid(index))
}

public ShowVGUIMenu_Pre(const index, VGUIMenu:menuType, const bitsSlots, szOldMenu[])
{
	if(csdm_spec_menu_always && menuType == VGUI_Menu_Team) {
		SetHookChainArg(3, ATYPE_INTEGER, (bitsSlots | MENU_KEY_6))
		SetHookChainArg(4, ATYPE_STRING, "#IG_Team_Select_Spect")
	}
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
	else if(equali(szKey, "allow_reset_score"))
	{
		g_bAllowResetScore = true
	}
	else if(equali(szKey, "spec_menu_always"))
	{
		csdm_spec_menu_always = true
	}
	else if(equali(szKey, "unlimited_team_changes"))
	{
		csdm_unlimited_team_changes = true
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

public hCMD_ResetScore(const pPlayer) {
	if(!g_bAllowResetScore)
		return PLUGIN_CONTINUE

	if(is_nullent(pPlayer))
		return PLUGIN_CONTINUE

	new ret;
	ExecuteForward(g_eCustomForwards[iFwdPlayerResetScore], ret, pPlayer)

	if(ret == PLUGIN_HANDLED)
		return PLUGIN_CONTINUE

	set_entvar(pPlayer, var_frags, 0.0)
	set_member(pPlayer, m_iDeaths, 0)

	client_print_color(pPlayer, print_team_grey, "^4[CSDM] %L", pPlayer, "CHAT_RESETSCORE")

	return PLUGIN_HANDLED
}

public SelectRandomAppearance(data) {
	new index = find_player("km", data);

	if(index)
		rg_internal_cmd(index, "joinclass", "5")
}
