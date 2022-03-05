#include <amxmodx>
#include <amxmisc>
#include <csdm>
#include <fakemeta>
#include <xs>


#define IsVectorZero(%1) 				(%1[X] == 0.0 && %1[Y] == 0.0 && %1[Z] == 0.0)
#define IsPlayer(%1)					(1 <= %1 <= MaxClients)

#define FIND_ENT_IN_SPHERE(%1,%2,%3) 	engfunc(EngFunc_FindEntityInSphere, %1, %2, %3)

const MAX_SPAWNS = 64
const Float:MIN_SPAWN_RADIUS = 450.0 		// beta

// spawn editor options
const MAX_SEARCH_DISTANCE = 2500
const Float:ADD_Z_POSITION = 2.0

new const Float:g_flGravityValues[] = {1.0, 0.5, 0.25, 0.15, 0.05}

const MENU_KEY_BITS = (MENU_KEY_1|MENU_KEY_2|MENU_KEY_3|MENU_KEY_4|MENU_KEY_5|MENU_KEY_6|MENU_KEY_8)
const FORCE_VIEW_ANGLES = 1

enum coord_e { Float:X, Float:Y, Float:Z }

enum
{
	FAILED_CREATE,
	FILE_SAVED,
	FILE_DELETED
}

new const g_szModel[] = "models/player/vip/vip.mdl"
new const g_szClassName[] = "view_spawn"
new const g_szEditorMenuTitle[] = "SpawnEditor"



new HookChain:g_hGetPlayerSpawnSpot

new Float:g_vecSpotOrigin[MAX_SPAWNS][coord_e],
	Float:g_vecSpotVAngles[MAX_SPAWNS][coord_e],
	Float:g_vecSpotAngles[MAX_SPAWNS][coord_e]

new Float:g_vecLastOrigin[MAX_CLIENTS + 1][coord_e],
	Float:g_vecLastAngles[MAX_CLIENTS + 1][coord_e],
	Float:g_vecLastVAngles[MAX_CLIENTS + 1][coord_e]

new g_pAimedEntity[MAX_CLIENTS + 1], g_iLastSpawnIndex[MAX_CLIENTS + 1], bool:g_bFirstSpawn[MAX_CLIENTS + 1]
new g_szSpawnDirectory[PLATFORM_MAX_PATH], g_szSpawnFile[PLATFORM_MAX_PATH + 32], g_szMapName[32]
new g_iTotalPoints, g_iEditorMenuID, bool:g_bEditSpawns, bool:g_bNotSaved
new g_iGravity

public plugin_precache()
{
	precache_model(g_szModel)
}

public plugin_init()
{
	register_plugin("CSDM Spawn Manager", CSDM_VERSION, "wopox1337")
	register_concmd("csdm_edit_spawns", "ConCmd_EditSpawns", ADMIN_MAP, "Edits spawn configuration")
	register_clcmd("nightvision", "ClCmd_Nightvision")
	register_menucmd((g_iEditorMenuID = register_menuid(g_szEditorMenuTitle)), MENU_KEY_BITS, "EditorMenuHandler")

	DisableHookChain(g_hGetPlayerSpawnSpot = RegisterHookChain(RG_CSGameRules_GetPlayerSpawnSpot, "CSGameRules_GetPlayerSpawnSpot", .post = false))
}

public plugin_cfg()
{
	new iLen = get_localinfo("amxx_configsdir", g_szSpawnDirectory, charsmax(g_szSpawnDirectory))
	formatex(g_szSpawnDirectory[iLen], charsmax(g_szSpawnDirectory) - iLen, "%s/%s/%s", g_szSpawnDirectory[iLen], g_szMainDir, g_szSpawnDir)
	MakeDir(g_szSpawnDirectory)

	get_mapname(g_szMapName, charsmax(g_szMapName))
	formatex(g_szSpawnFile, charsmax(g_szSpawnFile), "%s/%s.spawns.cfg", g_szSpawnDirectory, g_szMapName)
	LoadPoints()
}

public plugin_end()
{
	if(g_bEditSpawns && g_bNotSaved) // autosave
	{
		MakeDir(g_szSpawnDirectory)
		SavePoints()
	}
}

public CSDM_Initialized(const szVersion[])
{
	if(!szVersion[0])
		pause("ad")
}

public CSDM_ExecuteCVarValues()
{
	if(g_iTotalPoints)
	{
		set_member_game(m_iSpawnPointCount_Terrorist, get_member_game(m_iSpawnPointCount_Terrorist) + (g_iTotalPoints / 2))
		set_member_game(m_iSpawnPointCount_CT, get_member_game(m_iSpawnPointCount_CT) + (g_iTotalPoints / 2))
	}
}

public CSDM_RestartRound(const bool:bNewGame)
{
	if(bNewGame) {
		ArraySet(g_iLastSpawnIndex, INVALID_INDEX)
	}
}

public client_connect(pPlayer)
{
	g_bFirstSpawn[pPlayer] = true
}

public client_putinserver(pPlayer)
{
	g_pAimedEntity[pPlayer] = NULLENT
	g_iLastSpawnIndex[pPlayer] = INVALID_INDEX
	g_bFirstSpawn[pPlayer] = false
}

public ClCmd_Nightvision(const pPlayer, const level)
{
	if(!g_bEditSpawns || !is_user_alive(pPlayer) || ~get_user_flags(pPlayer) & level)
		return PLUGIN_CONTINUE

	return ShowEditorMenu(pPlayer)
}

public ConCmd_EditSpawns(const pPlayer, const level)
{
	if(!is_user_alive(pPlayer) || !access(pPlayer, level))
		return PLUGIN_HANDLED

	if(g_bEditSpawns)
	{
		if(g_bNotSaved && SavePoints() == FAILED_CREATE)
		{
			console_print(pPlayer, "[CSDM] Autosave is failed. Please try again.")
			return ShowEditorMenu(pPlayer)
		}

		console_print(pPlayer, "[CSDM] Spawn editor disabled.")
		CloseOpenedMenu(pPlayer)
		RemoveAllSpotEntitys()
		g_bEditSpawns = false

		set_entvar(pPlayer, var_gravity, 1.0)
		return PLUGIN_HANDLED
	}

	console_print(pPlayer, "[CSDM] Spawn editor enabled.")
	MakeAllSpotEntitys()
	g_bEditSpawns = true

	set_entvar(pPlayer, var_gravity, g_flGravityValues[g_iGravity])
	return ShowEditorMenu(pPlayer)
}

public CSGameRules_GetPlayerSpawnSpot(const pPlayer)
{
	if(RandomSpawn(pPlayer))
	{
		SetHookChainReturn(ATYPE_INTEGER, pPlayer)
		return HC_SUPERCEDE
	}

	return HC_CONTINUE
}

RandomSpawn(const pPlayer)
{
	if(!g_iTotalPoints || g_bFirstSpawn[pPlayer])
		return false

	new iRand = random(g_iTotalPoints - 1), iAttempts, iLast = g_iLastSpawnIndex[pPlayer]
	do
	{
		iAttempts++
		 /* && IsHullVacant(g_vecSpotOrigin[iRand], HULL_HUMAN, DONT_IGNORE_MONSTERS) */
		if(iRand != iLast && !IsVectorZero(g_vecSpotOrigin[iRand]) && !CheckDistance(pPlayer, g_vecSpotOrigin[iRand]))
		{
			SetPlayerPosition(pPlayer, g_vecSpotOrigin[iRand], g_vecSpotVAngles[iRand])
			g_iLastSpawnIndex[pPlayer] = iRand

			return true
		}

		if(++iRand >= g_iTotalPoints) {
			iRand = random(g_iTotalPoints - 1)
		}

	} while(iAttempts <= g_iTotalPoints)

	return false
}

bool:CheckDistance(const pPlayer, const Float:vecOrigin[coord_e])
{
	new pEntity = NULLENT
	while((pEntity = FIND_ENT_IN_SPHERE(pEntity, vecOrigin, MIN_SPAWN_RADIUS)))
	{
		if(IsPlayer(pEntity) && pEntity != pPlayer && get_entvar(pEntity, var_deadflag) == DEAD_NO) {
			// server_print("Client %i fount! skip...", pEntity)
			return true
		}
	}

	return false
}

public ShowEditorMenu(const pPlayer)
{
	new szMenu[512], Float:vecOrigin[coord_e], bitKeys, iLen
	get_entvar(pPlayer, var_origin, vecOrigin)
	iLen = formatex(szMenu, charsmax(szMenu), "\ySpawn Editor^n^n")
	bitKeys |= g_bNotSaved ? (MENU_KEY_2|MENU_KEY_5|MENU_KEY_6|MENU_KEY_8) : (MENU_KEY_2|MENU_KEY_5|MENU_KEY_6)

	if(!IsVectorZero(g_vecLastOrigin[pPlayer])) {
		bitKeys |= MENU_KEY_4
	}

	if(g_pAimedEntity[pPlayer] == NULLENT)
	{
		iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen,
			"%s^n^n\
			\y2. \wMark aimed spawn^n\
			\d3. Teleport me^n\
			%s^n^n",
			(g_iTotalPoints >= MAX_SPAWNS) ? "\d1. Add new spawn\w(\rMax limit reached!\w)" : "\y1. \wAdd new spawn",

			!IsVectorZero(g_vecLastOrigin[pPlayer]) ? "\y4. \wCancel delete" : "\d4. Delete spawn"
		)

		bitKeys |= (g_iTotalPoints >= MAX_SPAWNS) ? 0 : MENU_KEY_1
	}
	else
	{
		iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen,
			"\y1. \wUpdate position^n^n\
			\y2. \wUnmark marked spawn^n\
			\y3. \wTeleport me^n\
			\y4. %s^n^n",
			!IsVectorZero(g_vecLastOrigin[pPlayer]) ? "\wCancel delete" : "\rDelete spawn"
		)

		bitKeys |= (MENU_KEY_1|MENU_KEY_3|MENU_KEY_4)
	}

	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen,
		"\y5. \wRefresh info^n\
		\y6. \wGravity \y%0.2f^n^n\
		%s^n", g_flGravityValues[g_iGravity],
		g_bNotSaved ? "\y8. \wSave manual" : "\d8. Save manual"
	)

	formatex(szMenu[iLen], charsmax(szMenu) - iLen,
		"^n\wTotal spawns: \y%d^n\wCurrent position: \rX \y%0.f \rY \y%0.f \rZ \y%0.f",
		g_iTotalPoints, vecOrigin[X], vecOrigin[Y], vecOrigin[Z]
	)

	show_menu(pPlayer, bitKeys, szMenu, .title = g_szEditorMenuTitle)
	return PLUGIN_HANDLED
}

public EditorMenuHandler(const pPlayer, iKey)
{
	if(!g_bEditSpawns)
		return PLUGIN_HANDLED

	iKey++
	switch(iKey)
	{
		case 1: {
			g_bNotSaved = bool:(g_pAimedEntity[pPlayer] == NULLENT ? AddSpawn(pPlayer) : MoveSpawn(pPlayer, g_pAimedEntity[pPlayer]))
			g_vecLastOrigin[pPlayer][X] = g_vecLastOrigin[pPlayer][Y] = g_vecLastOrigin[pPlayer][Z] = 0.0
		}
		case 2:
		{
			if(g_pAimedEntity[pPlayer] == NULLENT)
			{
				if(!SetAimedEntity(pPlayer)) {
					client_print(pPlayer, print_center, "Spawn entity not found!")
				}
			}
			else
			{
				ClearAimedEntity(pPlayer)
				// SetAimedEntity(pPlayer)
			}
		}
		case 3: TeleportToAimed(pPlayer, g_pAimedEntity[pPlayer])
		case 4:
		{
			g_bNotSaved = bool:(IsVectorZero(g_vecLastOrigin[pPlayer]) ? DeleteSpawn(pPlayer, g_pAimedEntity[pPlayer]) : AddSpawn(pPlayer, true))
		}
		case 5:
		{
			new Float:vecOrigin[coord_e]
			get_entvar(pPlayer, var_origin, vecOrigin)

			client_print_color(pPlayer, print_team_grey,
				"Total spawns: ^4%d ^1Current position: ^3X ^4%0.f ^3Y ^4%0.f ^3Z ^4%0.f",
					g_iTotalPoints, vecOrigin[X], vecOrigin[Y], vecOrigin[Z])
		}
		case 6:
		{
			if(g_iGravity++ >= sizeof(g_flGravityValues)-1)
				g_iGravity = 0

			set_entvar(pPlayer, var_gravity, g_flGravityValues[g_iGravity])
		}
		case 8:
		{
			static const szResultPrint[][] = {"Failed to create file!^rPlease try again", "Saved successfully", "File deleted"}
			client_print(pPlayer, print_center, "%s", szResultPrint[SavePoints()])
		}
	}

	return ShowEditorMenu(pPlayer)
}

bool:AddSpawn(const pPlayer, bool:bUndo = false)
{
	new Float:vecOrigin[coord_e], Float:vecAngles[coord_e], Float:vecVAngles[coord_e], pEntity = NULLENT

	if((pEntity = CreateEntity()) == NULLENT)
		return false

	if(bUndo)
	{
		SetPosition(pEntity, g_vecLastOrigin[pPlayer], g_vecLastAngles[pPlayer], g_vecLastVAngles[pPlayer])
		SetAimedEntity(pPlayer, pEntity, false)
	}
	else
	{
		GetPosition(pPlayer, vecOrigin, vecAngles, vecVAngles)
		vecOrigin[Z] += ADD_Z_POSITION

		if(!IsFreeSpace(pPlayer, vecOrigin))
			return false

		SetPosition(pEntity, vecOrigin, vecAngles, vecVAngles)
	}

	g_iTotalPoints = min(MAX_SPAWNS, ++g_iTotalPoints)

	return true
}

bool:MoveSpawn(const pPlayer, const pEntity = NULLENT)
{
	new Float:vecOrigin[coord_e], Float:vecAngles[coord_e], Float:vecVAngles[coord_e]
	GetPosition(pPlayer, vecOrigin, vecAngles, vecVAngles)
	vecOrigin[Z] += ADD_Z_POSITION

	if(IsFreeSpace(pPlayer, vecOrigin))
	{
		SetPosition(pEntity, vecOrigin, vecAngles, vecVAngles)
		return true
	}

	return false
}

bool:DeleteSpawn(const pPlayer, const pEntity = NULLENT)
{
	if(is_nullent(pEntity))
		return false

	GetPosition(pEntity, g_vecLastOrigin[pPlayer], g_vecLastAngles[pPlayer], g_vecLastVAngles[pPlayer])

	g_pAimedEntity[pPlayer] = NULLENT
	REMOVE_ENTITY(pEntity)

	g_iTotalPoints = max(0, --g_iTotalPoints)

	return true
}

bool:TeleportToAimed(const pPlayer, const pEntity = NULLENT)
{
	if(pEntity == NULLENT)
		return false

	new Float:vecOrigin[coord_e], Float:vecAngles[coord_e], Float:vecVAngles[coord_e]
	GetPosition(pEntity, vecOrigin, vecAngles, vecVAngles)

	if(IsFreeSpace(pPlayer, vecOrigin))
	{
		SetPlayerPosition(pPlayer, vecOrigin, vecVAngles)
		return true
	}

	return false
}

LoadPoints()
{
	new pFile
	if(!(pFile = fopen(g_szSpawnFile, "rt")))
	{
		server_print("[CSDM] No spawn points file found ^"%s^"", g_szMapName)
		return
	}

	new szDatas[MAX_LINE_LEN], szOrigin[coord_e][6], szTeam[3], szAngles[coord_e][6], szVAngles[coord_e][6]
	while(!feof(pFile))
	{
		fgets(pFile, szDatas, charsmax(szDatas))
		trim(szDatas)

		if(!szDatas[0] || IsCommentLine(szDatas))
			continue

		if(parse(szDatas,
					szOrigin[X], 5, szOrigin[Y], 5, szOrigin[Z], 5,
					szAngles[X], 5, szAngles[Y], 5, szAngles[Z], 5,
					szTeam, charsmax(szTeam), // ignore team param 7
					szVAngles[X], 5, szVAngles[Y], 5, szVAngles[Z], 5
				) != 10)
		{
			continue // ignore invalid lines
		}

		if(g_iTotalPoints >= MAX_SPAWNS)
		{
			server_print("[CSDM] Max limit %d reached!", MAX_SPAWNS)
			break
		}

		g_vecSpotOrigin[g_iTotalPoints][X] = str_to_float(szOrigin[X])
		g_vecSpotOrigin[g_iTotalPoints][Y] = str_to_float(szOrigin[Y])
		g_vecSpotOrigin[g_iTotalPoints][Z] = str_to_float(szOrigin[Z])

		g_vecSpotAngles[g_iTotalPoints][X] = str_to_float(szAngles[X])
		g_vecSpotAngles[g_iTotalPoints][Y] = str_to_float(szAngles[Y])
		// g_vecSpotAngles[g_iTotalPoints][Z] = str_to_float(szAngles[Z])

		g_vecSpotVAngles[g_iTotalPoints][X] = str_to_float(szVAngles[X])
		g_vecSpotVAngles[g_iTotalPoints][Y] = str_to_float(szVAngles[Y])
		// g_vecSpotVAngles[g_iTotalPoints][Z] = str_to_float(szVAngles[Z])

		g_iTotalPoints++
	}
	if(g_iTotalPoints)
	{
		server_print("[CSDM] Loaded %d spawn points for map ^"%s^"", g_iTotalPoints, g_szMapName)
		EnableHookChain(g_hGetPlayerSpawnSpot)
	}

	fclose(pFile)
}

SavePoints()
{
	if(!g_iTotalPoints)
	{
		delete_file(g_szSpawnFile)
		DisableHookChain(g_hGetPlayerSpawnSpot)
		return FILE_DELETED
	}

	new pFile, pEntity = NULLENT
	if(!(pFile = fopen(g_szSpawnFile, "wt")))
	{
		MakeDir(g_szSpawnDirectory, false)
		return FAILED_CREATE
	}

	fprintf(pFile, "// File generated by ^"CSDM Spawn Manager^" Version: %s^n// Total spawns: %d^n^n", CSDM_VERSION, g_iTotalPoints)
	ClearAllArrays()

	while((pEntity = rg_find_ent_by_class(pEntity, g_szClassName)))
	{
		if(g_iTotalPoints >= MAX_SPAWNS)
		{
			server_print("[CSDM] Max limit %d reached!", MAX_SPAWNS)
			break
		}

		GetPosition(pEntity, g_vecSpotOrigin[g_iTotalPoints], g_vecSpotAngles[g_iTotalPoints], g_vecSpotVAngles[g_iTotalPoints])
		if(IsVectorZero(g_vecSpotOrigin[g_iTotalPoints]))
			continue

		fprintf(pFile,
			"%-6.f %-6.f %-6.f %-4.f %-5.f %-2.f %-2.1d %-4.f %-5.f %-1.f^n",
			g_vecSpotOrigin[g_iTotalPoints][X], g_vecSpotOrigin[g_iTotalPoints][Y], g_vecSpotOrigin[g_iTotalPoints][Z],
			g_vecSpotAngles[g_iTotalPoints][X],  g_vecSpotAngles[g_iTotalPoints][Y],  g_vecSpotAngles[g_iTotalPoints][Z],
			0, // ignore team param 7
			g_vecSpotVAngles[g_iTotalPoints][X],  g_vecSpotVAngles[g_iTotalPoints][Y], g_vecSpotVAngles[g_iTotalPoints][Z]
		)

		g_iTotalPoints++
	}

	if(g_iTotalPoints)
		EnableHookChain(g_hGetPlayerSpawnSpot)
	else
		DisableHookChain(g_hGetPlayerSpawnSpot)

	g_bNotSaved = false
	fclose(pFile)

	return FILE_SAVED
}

MakeAllSpotEntitys()
{
	if(!g_iTotalPoints)
		return

	for(new i = 0; i < MAX_SPAWNS; i++)
	{
		if(IsVectorZero(g_vecSpotOrigin[i]))
			continue

		SetPosition(CreateEntity(), g_vecSpotOrigin[i], g_vecSpotAngles[i], g_vecSpotVAngles[i])
	}
}

RemoveAllSpotEntitys()
{
	new pEntity = NULLENT
	ArraySet(g_pAimedEntity, NULLENT)
	while((pEntity = rg_find_ent_by_class(pEntity, g_szClassName)))
	{
		REMOVE_ENTITY(pEntity)
	}
}

CreateEntity()
{
	new pEntity = rg_create_entity("info_target")
	if(is_nullent(pEntity))
	{
		server_print("Failed to create entity")
		return NULLENT
	}

	set_entvar(pEntity, var_classname, g_szClassName)
	SET_MODEL(pEntity, g_szModel)
	// SET_SIZE(pEntity, VECTOR_ZERO, VECTOR_ZERO)
	set_entvar(pEntity, var_solid, SOLID_SLIDEBOX)

	rg_animate_entity(pEntity, ACT_IDLE)

	return pEntity
}

SetPlayerPosition(const pPlayer, const Float:vecOrigin[coord_e], const Float:vecAngles[coord_e])
{
	SET_ORIGIN(pPlayer, vecOrigin)
	set_entvar(pPlayer, var_velocity, VECTOR_ZERO)
	set_entvar(pPlayer, var_v_angle, VECTOR_ZERO)
	set_entvar(pPlayer, var_angles, vecAngles)
	set_entvar(pPlayer, var_punchangle, VECTOR_ZERO)
	set_entvar(pPlayer, var_fixangle, FORCE_VIEW_ANGLES)
}

SetPosition(const pEntity, const Float:vecOrigin[coord_e], const Float:vecAngles[coord_e], const Float:vecVAngles[coord_e])
{
	if(pEntity != NULLENT)
	{
		SET_ORIGIN(pEntity, vecOrigin)
		set_entvar(pEntity, var_angles, vecAngles)
		set_entvar(pEntity, var_v_angle, vecVAngles) // temporary save
	}
}

GetPosition(const pEntity, Float:vecOrigin[coord_e], Float:vecAngles[coord_e], Float:vecVAngles[coord_e])
{
	get_entvar(pEntity, var_origin, vecOrigin)
	get_entvar(pEntity, var_angles, vecAngles)
	get_entvar(pEntity, var_v_angle, vecVAngles)

	if(get_entvar(pEntity, var_flags) & FL_DUCKING)
		vecOrigin[Z] += 18.0
}

bool:SetAimedEntity(const pPlayer, pEntity = NULLENT, bool:bPrint = true)
{
	if(pEntity > 0 || (pEntity = FindEntityByAim(pPlayer)) != NULLENT)
	{
		rg_animate_entity(pEntity, ACT_RUN, 1.0)
		rg_set_rendering(pEntity, kRenderFxGlowShell, Vector(0, 250, 0), 20.0)

		g_pAimedEntity[pPlayer] = pEntity
		if(bPrint) {
			client_print(pPlayer, print_center, "Aimed entity index %i", g_pAimedEntity[pPlayer])
		}

		g_vecLastOrigin[pPlayer][X] = g_vecLastOrigin[pPlayer][Y] = g_vecLastOrigin[pPlayer][Z] = 0.0

		return true
	}

	return false
}

ClearAimedEntity(const pPlayer)
{
	rg_animate_entity(g_pAimedEntity[pPlayer], ACT_IDLE)
	rg_set_rendering(g_pAimedEntity[pPlayer])
	g_pAimedEntity[pPlayer] = NULLENT
}

ClearAllArrays()
{
	g_iTotalPoints = 0
	for(new i = 0; i < MAX_SPAWNS; i++)
	{
		g_vecSpotOrigin[i][X] = g_vecSpotOrigin[i][Y] = g_vecSpotOrigin[i][Z] = 0.0
		g_vecSpotVAngles[i][X] = g_vecSpotVAngles[i][Y] = g_vecSpotVAngles[i][Z] = 0.0
		g_vecSpotAngles[i][X] = g_vecSpotAngles[i][Y] = g_vecSpotAngles[i][Z] = 0.0
	}
}

CloseOpenedMenu(const pPlayer)
{
	new iMenuID, iKeys
	get_user_menu(pPlayer, iMenuID, iKeys)
	if(iMenuID == g_iEditorMenuID)
	{
		menu_cancel(pPlayer)
		show_menu(pPlayer, 0, "^n", 1)
	}
}

stock rg_animate_entity(const pEntity, const Activity:iSequence, const Float:flFramerate = 0.0)
{
	set_entvar(pEntity, var_sequence, iSequence)
	set_entvar(pEntity, var_framerate, flFramerate)
}

stock FindEntityByAim(const pPlayer)
{
	new pEntity = NULLENT, dummy

	SetEntitysSolid(true)
	get_user_aiming(pPlayer, pEntity, dummy, MAX_SEARCH_DISTANCE)
	SetEntitysSolid(false)

	return (FClassnameIs(pEntity, g_szClassName)) ? pEntity : NULLENT
}

SetEntitysSolid(const bool:bSolid)
{
	new pEntity = NULLENT
	while((pEntity = rg_find_ent_by_class(pEntity, g_szClassName)))
	{
		if(!bSolid)
			SET_SIZE(pEntity, VECTOR_ZERO, VECTOR_ZERO)
		else
			SET_SIZE(pEntity, Vector(-16, -16, -36), Vector(16, 16, 36))
	}
}

bool:IsFreeSpace(const pPlayer, const Float:vecOrigin[coord_e])
{
	if(!IsHullVacant(vecOrigin, HULL_HUMAN, DONT_IGNORE_MONSTERS, pPlayer))
	{
		client_print(pPlayer, print_center, "No free space!")
		return false
	}

	return true
}

// checks if a space is vacant, by VEN
stock bool:IsHullVacant(const Float:vecOrigin[coord_e], const iHullNumber, const fNoMonsters, pSkipEnt = 0)
{
	new ptr
	engfunc(EngFunc_TraceHull, vecOrigin, vecOrigin, fNoMonsters, iHullNumber, pSkipEnt, ptr)

	return bool:(!get_tr2(ptr, TR_StartSolid) && !get_tr2(ptr, TR_AllSolid) && get_tr2(ptr, TR_InOpen))
}
