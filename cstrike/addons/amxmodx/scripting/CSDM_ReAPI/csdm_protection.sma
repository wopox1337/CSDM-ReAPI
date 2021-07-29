#include <amxmodx>
#include <csdm>


new Float:g_fImmunityTime
new Float:g_flRenderAlpha = 10.0
new Float:g_flTeamColors[TeamName][3] = {
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

	RegisterHookChain(RG_CBasePlayer_SetSpawnProtection, "CBasePlayer_SetSpawnProtection", .post = true)
	RegisterHookChain(RG_CBasePlayer_RemoveSpawnProtection, "CBasePlayer_RemoveSpawnProtection", .post = true)
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
	SetEffects(pPlayer)
}

public CBasePlayer_RemoveSpawnProtection(const pPlayer)
{
	RemoveEffects(pPlayer)
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
	else if(equali(szKey, "render_color_", 13))
	{
		new szRed[4], szGreen[4], szBlue[4]
		strtolower(szKey) // render_color_C or render_color_c
		new TeamName:iTeam = szKey[13] == 'c' ? TEAM_CT : szKey[13] == 't' ? TEAM_TERRORIST : TEAM_UNASSIGNED // invalid team

		if(parse(szValue, szRed, charsmax(szRed), szGreen, charsmax(szGreen), szBlue, charsmax(szBlue)) == 3)
		{
			g_flTeamColors[iTeam][0] = floatclamp(str_to_float(szRed), 1.0, 255.0)
			g_flTeamColors[iTeam][1] = floatclamp(str_to_float(szGreen), 1.0, 255.0)
			g_flTeamColors[iTeam][2] = floatclamp(str_to_float(szBlue), 1.0, 255.0)
		}
		else if(equali(szValue, "random"))
		{
			g_flTeamColors[iTeam][0] = g_flTeamColors[iTeam][1] = g_flTeamColors[iTeam][2] = 0.0
		}
	}
	else if(equali(szKey, "render_alpha"))
	{
		g_flRenderAlpha = str_to_float(szValue)
	}
}

SetEffects(const pPlayer)
{
// https://github.com/s1lentq/ReGameDLL_CS/blob/bc2c3176e46e2c32ebc0110e7df879ea7ddbfafa/regamedll/dlls/player.cpp#L9532
	set_entvar(pPlayer, var_rendermode, kRenderFxNone)

	new TeamName:iTeam = get_member(pPlayer, m_iTeam)
	new bool: isRandomColor = (!g_flTeamColors[iTeam][0] && !g_flTeamColors[iTeam][1] && !g_flTeamColors[iTeam][2])
	if(!isRandomColor) {
		rg_set_rendering(pPlayer, kRenderFxGlowShell, g_flTeamColors[iTeam], g_flRenderAlpha)

		return
	}

	new Float:flColor[3]
	flColor[0] = random_float(1.0, 255.0)
	flColor[1] = random_float(1.0, 255.0)
	flColor[2] = random_float(1.0, 255.0)

	rg_set_rendering(pPlayer, kRenderFxGlowShell, flColor, g_flRenderAlpha)
}

RemoveEffects(const pPlayer)
{
	if(is_user_connected(pPlayer))
	{
		rg_set_rendering(pPlayer)
	}
}
