#include <amxmodx>
#include <csdm>


#define IsPlayer(%1)				(1 <= (%1) <= g_iMaxPlayers)
#define PlayerTask(%1)				(%1 + PROTECTION_TASK_ID)
#define GetPlayerByTaskID(%1)		(%1 - PROTECTION_TASK_ID)

const PROTECTION_TASK_ID = 216897

enum color_e { Float:R, Float:G, Float:B }

enum
{
	STATUSICON_HIDE,
	STATUSICON_SHOW,
	STATUSICON_FLASH
}

new bool:g_bIsProtected[MAX_CLIENTS + 1]
new g_iMaxPlayers

new Float:g_flRenderAlpha = 10.0, bool:g_bBlockDamage = true, Float: g_fImmunityTime;
new Float:g_flTeamColors[TeamName][color_e] =
{
	{0.0, 0.0, 0.0},
	{235.0, 0.0, 0.0}, // TEAM_TERRORIST
	{0.0, 0.0, 235.0}, // TEAM_CT
	{0.0, 0.0, 0.0}
}

public OnConfigsExecuted()
{
	set_cvar_float("mp_respawn_immunitytime", g_fImmunityTime)
}

public plugin_init()
{
	register_plugin("CSDM Protection", CSDM_VERSION, "wopox1337")

	if(g_fImmunityTime > 0.0) {
		if(g_bBlockDamage)
			RegisterHookChain(RG_CSGameRules_FPlayerCanTakeDamage, "CSGameRules_FPlayerCanTakeDmg", .post = false)

		RegisterHookChain(RG_CBasePlayer_SetSpawnProtection, "CBasePlayer_SetSpawnProtection", .post = true)
		RegisterHookChain(RG_CBasePlayer_RemoveSpawnProtection, "CBasePlayer_RemoveSpawnProtection", .post = true)

	}

	g_iMaxPlayers = get_maxplayers()
}

public CSDM_Initialized(const szVersion[])
{
	if(!szVersion[0])
		pause("ad")
}

public CSDM_ConfigurationLoad(const ReadTypes:iReadAction)
{
	CSDM_RegisterConfig("protection", "ReadCfg")
}

public CBasePlayer_SetSpawnProtection(const pPlayer, Float: time)
{
	SetEffects(pPlayer, time)
}

public CBasePlayer_RemoveSpawnProtection(const pPlayer)
{
	RemoveEffects(pPlayer)
}

public CSGameRules_FPlayerCanTakeDmg(const pPlayer, const pAttacker)
{
	if(pPlayer == pAttacker || !IsPlayer(pAttacker))
		return HC_CONTINUE

	if(g_bIsProtected[pAttacker]) // protected attacker can't take damage
	{
		SetHookChainReturn(ATYPE_INTEGER, false)
		return HC_SUPERCEDE
	}

	return HC_CONTINUE
}

public ReadCfg(const szLineData[], const iSectionID)
{
	new szKey[MAX_KEY_LEN], szValue[MAX_VALUE_LEN], szSign[2]
	if(!ParseConfigKey(szLineData, szKey, szSign, szValue))
		return

	if(equali(szKey, "protection_time"))
	{
		g_fImmunityTime = str_to_float(szValue)
	}
	else if(equali(szKey, "block_damage"))
	{
		g_bBlockDamage = bool:(str_to_num(szValue))
	}
	else if(equali(szKey, "render_color_", 13))
	{
		new szRed[4], szGreen[4], szBlue[4]
		strtolower(szKey) // render_color_C or render_color_c
		new TeamName:iTeam = szKey[13] == 'c' ? TEAM_CT : szKey[13] == 't' ? TEAM_TERRORIST : TEAM_UNASSIGNED // invalid team

		if(parse(szValue, szRed, charsmax(szRed), szGreen, charsmax(szGreen), szBlue, charsmax(szBlue)) == 3)
		{
			g_flTeamColors[iTeam][R] = floatclamp(str_to_float(szRed), 1.0, 255.0)
			g_flTeamColors[iTeam][G] = floatclamp(str_to_float(szGreen), 1.0, 255.0)
			g_flTeamColors[iTeam][B] = floatclamp(str_to_float(szBlue), 1.0, 255.0)
		}
		else if(equali(szValue, "random"))
		{
			g_flTeamColors[iTeam][R] = g_flTeamColors[iTeam][G] = g_flTeamColors[iTeam][B] = 0.0
		}
	}
	else if(equali(szKey, "render_alpha"))
	{
		g_flRenderAlpha = str_to_float(szValue)
	}
}

SetEffects(const pPlayer, Float: time)
{
// https://github.com/s1lentq/ReGameDLL_CS/blob/bc2c3176e46e2c32ebc0110e7df879ea7ddbfafa/regamedll/dlls/player.cpp#L9532
	set_entvar(pPlayer, var_rendermode, kRenderFxNone)

	new TeamName:iTeam = get_member(pPlayer, m_iTeam)
	if(!g_flTeamColors[iTeam][R] && !g_flTeamColors[iTeam][G] && !g_flTeamColors[iTeam][B])
	{
		new Float:flColor[color_e]
		flColor[R] = random_float(1.0, 255.0)
		flColor[G] = random_float(1.0, 255.0)
		flColor[B] = random_float(1.0, 255.0)

		rg_set_rendering(pPlayer, kRenderFxGlowShell, flColor, g_flRenderAlpha)
	}
	else rg_set_rendering(pPlayer, kRenderFxGlowShell, g_flTeamColors[iTeam], g_flRenderAlpha)
}
