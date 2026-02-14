#pragma semicolon 1
#include <sourcemod>
#include <shop>
#include <multicolors>
#include <sdktools>
#include <keyvalues>
#include <clientprefs>

#pragma newdecls required

#define PLUGIN_NAME "Random Quiz"
#define PLUGIN_VERSION "5.0.2"
#define CONFIG_PATH "configs/random_quiz/questions.cfg"
#define MODE_ALL 0
#define MODE_MENUONLY 1
#define MODE_CHATONLY 2
#define MODE_DISABLED 3

ConVar g_cvEnabled;
ConVar g_cvMinCredits;
ConVar g_cvMaxCredits;
ConVar g_cvTimeout;
ConVar g_cvQuestionInterval;
ConVar g_cvMaxAttempts;
ConVar g_cvDebugMode;
ConVar g_cvMinNumber;
ConVar g_cvMaxNumber;
ConVar g_cvAllowCaseSensitive;
ConVar g_cvMenuPercentage;
ConVar g_cvMenuOptions;
ConVar g_cvMaxMenuTime;
ConVar g_cvQuestionTypeDefault;

Handle g_hQuestionTimer;
Handle g_hTimeoutTimer;
char g_sCurrentAnswer[128];
char g_sCurrentQuestion[256];
int g_iCorrectClient = -1;
int g_iAttempts[MAXPLAYERS+1];
float g_fTimeout;
int g_iQuestionCounter = 0;
int g_iCurrentReward = 0;
int g_iCurrentDifficulty = 1;
bool g_bMenuQuestion = false;
char g_sMenuAnswers[6][128];
int g_iMenuCorrectIndex = -1;
int g_iMenuPlayersAnswered[MAXPLAYERS+1];
QuestionType g_iCurrentQuestionType;

ArrayList g_arrScienceQuestions;
ArrayList g_arrProgrammingQuestions;
ArrayList g_arrGeneralQuestions;
ArrayList g_arrMathQuestions;
bool g_bConfigLoaded = false;
bool g_bQuestionAnswered = false;

Handle g_hCookieEnabled;
Handle g_hCookieMenuOnly;
Handle g_hCookieChatOnly;
Handle g_hCookieQuestionTypes;

enum struct ConfigQuestion {
    char question[256];
    char answer[128];
    int difficulty;
}

enum QuestionType {
    TYPE_MATH = 0,
    TYPE_SCIENCE,
    TYPE_PROGRAMMING,
    TYPE_GENERAL,
    TYPE_COUNT
}

enum QuestionDifficulty {
    DIFFICULTY_EASY = 1,
    DIFFICULTY_MEDIUM = 2,
    DIFFICULTY_HARD = 3
}

enum QuestionMode {
    MODE_CHAT = 0,
    MODE_MENU,
    MODE_COUNT
}

public Plugin myinfo = 
{
    name = PLUGIN_NAME,
    author = "+SyntX",
    description = "Random quiz with auto-generated math questions and menu support",
    version = PLUGIN_VERSION,
    url = "https://github.com/SyntX34 && https://steamcommunity.com/id/SyntX34/"
};

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    
    g_cvEnabled = CreateConVar("sm_randomquiz_enabled", "1", "Enable/disable Random Quiz plugin", _, true, 0.0, true, 1.0);
    g_cvMinCredits = CreateConVar("sm_randomquiz_mincredits", "50", "Minimum credits reward", _, true, 1.0);
    g_cvMaxCredits = CreateConVar("sm_randomquiz_maxcredits", "500", "Maximum credits reward", _, true, 5.0, true, 1000.0);
    g_cvTimeout = CreateConVar("sm_randomquiz_timeout", "30.0", "Time in seconds to answer question", _, true, 5.0, true, 120.0);
    g_cvQuestionInterval = CreateConVar("sm_randomquiz_interval", "120.0", "Seconds between questions", _, true, 30.0, true, 600.0);
    g_cvMaxAttempts = CreateConVar("sm_randomquiz_maxattempts", "3", "Maximum attempts per question", _, true, 1.0, true, 5.0);
    g_cvDebugMode = CreateConVar("sm_randomquiz_debug", "0", "Debug mode - shows extra information", _, true, 0.0, true, 1.0);
    g_cvMinNumber = CreateConVar("sm_randomquiz_min_number", "10", "Minimum number for math questions", _, true, 1.0);
    g_cvMaxNumber = CreateConVar("sm_randomquiz_max_number", "1000", "Maximum number for math questions", _, true, 10.0);
    g_cvAllowCaseSensitive = CreateConVar("sm_randomquiz_case_sensitive", "0", "Are answers case sensitive? (1=Yes, 0=No)", _, true, 0.0, true, 1.0);
    g_cvMenuPercentage = CreateConVar("sm_randomquiz_menu_percentage", "40", "Percentage of questions that will be menu-based (0-100)", _, true, 0.0, true, 100.0);
    g_cvMenuOptions = CreateConVar("sm_randomquiz_menu_options", "4", "Number of options in menu questions (2-6)", _, true, 2.0, true, 6.0);
    g_cvMaxMenuTime = CreateConVar("sm_randomquiz_max_menu_time", "15.0", "Maximum time for menu questions", _, true, 5.0, true, 30.0);
    g_cvQuestionTypeDefault = CreateConVar("sm_randomquiz_default_types", "15", "Default question types enabled (bitmask: 1=Math, 2=Science, 4=Programming, 8=General)", _, true, 1.0, true, 15.0);
    
    AutoExecConfig(true, "random_quiz");
    
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say2");
    AddCommandListener(Command_Say, "say_team");

    RegConsoleCmd("sm_quizsettings", Command_QuizSettings, "Open quiz settings menu");
    RegConsoleCmd("sm_quizmenu", Command_QuizMenu, "Open quiz settings menu");
    
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    
    g_hCookieEnabled = RegClientCookie("randomquiz_enabled", "Enable/disable quiz questions", CookieAccess_Protected);
    g_hCookieMenuOnly = RegClientCookie("randomquiz_menuonly", "Only show menu questions", CookieAccess_Protected);
    g_hCookieChatOnly = RegClientCookie("randomquiz_chatonly", "Only show chat questions", CookieAccess_Protected);
    g_hCookieQuestionTypes = RegClientCookie("randomquiz_types", "Question types enabled (bitmask)", CookieAccess_Protected);
    
    SetCookieMenuItem(CookieMenuHandler_QuizSettings, 0, "Quiz Settings");
    g_arrScienceQuestions = new ArrayList(sizeof(ConfigQuestion));
    g_arrProgrammingQuestions = new ArrayList(sizeof(ConfigQuestion));
    g_arrGeneralQuestions = new ArrayList(sizeof(ConfigQuestion));
    g_arrMathQuestions = new ArrayList(sizeof(ConfigQuestion));
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
        {
            g_iAttempts[i] = 0;
            g_iMenuPlayersAnswered[i] = 0;
            
            if(AreClientCookiesCached(i))
            {
                OnClientCookiesCached(i);
            }
        }
    }
}

public void OnClientCookiesCached(int client)
{
    if(!IsClientConnected(client) || IsFakeClient(client))
        return;
    
    char value[16];
    
    GetClientCookie(client, g_hCookieEnabled, value, sizeof(value));
    if(strlen(value) == 0)
    {
        SetClientCookie(client, g_hCookieEnabled, "1");
    }
    
    GetClientCookie(client, g_hCookieMenuOnly, value, sizeof(value));
    if(strlen(value) == 0)
    {
        SetClientCookie(client, g_hCookieMenuOnly, "0");
    }
    
    GetClientCookie(client, g_hCookieChatOnly, value, sizeof(value));
    if(strlen(value) == 0)
    {
        SetClientCookie(client, g_hCookieChatOnly, "0");
    }
    
    GetClientCookie(client, g_hCookieQuestionTypes, value, sizeof(value));
    if(strlen(value) == 0)
    {
        IntToString(g_cvQuestionTypeDefault.IntValue, value, sizeof(value));
        SetClientCookie(client, g_hCookieQuestionTypes, value);
    }
}

public void CookieMenuHandler_QuizSettings(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
    if(action == CookieMenuAction_DisplayOption)
    {
        Format(buffer, maxlen, "Quiz Settings");
    }
    else if(action == CookieMenuAction_SelectOption)
    {
        ShowSettingsMenu(client);
    }
}

public Action Command_QuizSettings(int client, int args)
{
    ShowSettingsMenu(client);
    return Plugin_Handled;
}

public Action Command_QuizMenu(int client, int args)
{
    ShowSettingsMenu(client);
    return Plugin_Handled;
}

void ShowSettingsMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Settings);
    menu.SetTitle("Quiz Settings\n \nConfigure your quiz preferences:");
    
    char enabledValue[16], menuOnlyValue[16], chatOnlyValue[16];
    GetClientCookie(client, g_hCookieEnabled, enabledValue, sizeof(enabledValue));
    GetClientCookie(client, g_hCookieMenuOnly, menuOnlyValue, sizeof(menuOnlyValue));
    GetClientCookie(client, g_hCookieChatOnly, chatOnlyValue, sizeof(chatOnlyValue));
    
    bool isEnabled = StringToInt(enabledValue) != 0;
    bool menuOnly = StringToInt(menuOnlyValue) != 0;
    bool chatOnly = StringToInt(chatOnlyValue) != 0;
    int currentMode = MODE_ALL;
    if(!isEnabled)
        currentMode = MODE_DISABLED;
    else if(menuOnly)
        currentMode = MODE_MENUONLY;
    else if(chatOnly)
        currentMode = MODE_CHATONLY;
    
    char display[64];
    char cleanDisplay[64];
    Format(display, sizeof(display), "Quiz: %s", isEnabled ? "{green}Enabled" : "{red}Disabled");
    StripColors(display, cleanDisplay, sizeof(cleanDisplay));
    menu.AddItem("toggle", cleanDisplay);
    
    char modeDesc[32];
    switch(currentMode)
    {
        case MODE_ALL: Format(modeDesc, sizeof(modeDesc), "{aqua}Chat & Menu");
        case MODE_MENUONLY: Format(modeDesc, sizeof(modeDesc), "{orange}Menu Only");
        case MODE_CHATONLY: Format(modeDesc, sizeof(modeDesc), "{lime}Chat Only");
        case MODE_DISABLED: Format(modeDesc, sizeof(modeDesc), "{red}Disabled");
    }
    
    Format(display, sizeof(display), "Question Mode: %s", modeDesc);
    StripColors(display, cleanDisplay, sizeof(cleanDisplay));
    menu.AddItem("mode", cleanDisplay);
    
    Format(display, sizeof(display), "Question Types");
    StripColors(display, cleanDisplay, sizeof(cleanDisplay));
    menu.AddItem("types", cleanDisplay);
    
    menu.AddItem("info", "Information & Help");
    
    menu.ExitButton = true;
    menu.ExitBackButton = false;
    menu.Display(client, MENU_TIME_FOREVER);
}

/*
bool IsQuizEnabledForClient(int client)
{
    if(!IsClientInGame(client) || IsFakeClient(client))
        return false;
    
    char enabledValue[8], chatOnlyValue[8], menuOnlyValue[8];
    GetClientCookie(client, g_hCookieEnabled, enabledValue, sizeof(enabledValue));
    GetClientCookie(client, g_hCookieChatOnly, chatOnlyValue, sizeof(chatOnlyValue));
    GetClientCookie(client, g_hCookieMenuOnly, menuOnlyValue, sizeof(menuOnlyValue));
    if(StringToInt(enabledValue) == 0)
        return false;
    
    return true;
}
*/

/*
bool IsMenuOnlyForClient(int client)
{
    char value[8];
    GetClientCookie(client, g_hCookieMenuOnly, value, sizeof(value));
    return StringToInt(value) != 0;
}
*/

public int MenuHandler_Settings(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "toggle"))
        {
            char value[16];
            GetClientCookie(client, g_hCookieEnabled, value, sizeof(value));
            bool isEnabled = StringToInt(value) != 0;
            
            SetClientCookie(client, g_hCookieEnabled, isEnabled ? "0" : "1");
            
            if(isEnabled)
            {
                CPrintToChat(client, "{aqua}[Quiz]{default} You have {red}disabled{default} quiz questions.");
            }
            else
            {
                SetClientCookie(client, g_hCookieMenuOnly, "0");
                SetClientCookie(client, g_hCookieChatOnly, "0");
                CPrintToChat(client, "{aqua}[Quiz]{default} You have {green}enabled{default} quiz questions. Mode: {aqua}Chat & Menu");
            }
        }
        else if(StrEqual(info, "mode"))
        {
            char enabledValue[16], menuOnlyValue[16], chatOnlyValue[16];
            GetClientCookie(client, g_hCookieEnabled, enabledValue, sizeof(enabledValue));
            GetClientCookie(client, g_hCookieMenuOnly, menuOnlyValue, sizeof(menuOnlyValue));
            GetClientCookie(client, g_hCookieChatOnly, chatOnlyValue, sizeof(chatOnlyValue));
            
            bool isEnabled = StringToInt(enabledValue) != 0;
            bool menuOnly = StringToInt(menuOnlyValue) != 0;
            bool chatOnly = StringToInt(chatOnlyValue) != 0;
            int currentMode = MODE_ALL;
            if(!isEnabled)
                currentMode = MODE_DISABLED;
            else if(menuOnly)
                currentMode = MODE_MENUONLY;
            else if(chatOnly)
                currentMode = MODE_CHATONLY;
            
            int nextMode = (currentMode + 1) % (MODE_DISABLED + 1);
            switch(nextMode)
            {
                case MODE_ALL:
                {
                    SetClientCookie(client, g_hCookieEnabled, "1");
                    SetClientCookie(client, g_hCookieMenuOnly, "0");
                    SetClientCookie(client, g_hCookieChatOnly, "0");
                    CPrintToChat(client, "{aqua}[Quiz]{default} Mode set to: {aqua}Chat & Menu{default} (all questions)");
                }
                case MODE_MENUONLY:
                {
                    SetClientCookie(client, g_hCookieEnabled, "1");
                    SetClientCookie(client, g_hCookieMenuOnly, "1");
                    SetClientCookie(client, g_hCookieChatOnly, "0");
                    CPrintToChat(client, "{aqua}[Quiz]{default} Mode set to: {orange}Menu Only{default} (no chat questions)");
                }
                case MODE_CHATONLY:
                {
                    SetClientCookie(client, g_hCookieEnabled, "1");
                    SetClientCookie(client, g_hCookieMenuOnly, "0");
                    SetClientCookie(client, g_hCookieChatOnly, "1");
                    CPrintToChat(client, "{aqua}[Quiz]{default} Mode set to: {lime}Chat Only{default} (no menu questions)");
                }
                case MODE_DISABLED:
                {
                    SetClientCookie(client, g_hCookieEnabled, "0");
                    SetClientCookie(client, g_hCookieMenuOnly, "0");
                    SetClientCookie(client, g_hCookieChatOnly, "0");
                    CPrintToChat(client, "{aqua}[Quiz]{default} Mode set to: {red}Disabled{default} (no questions)");
                }
            }
        }
        else if(StrEqual(info, "types"))
        {
            ShowQuestionTypesMenu(client);
            return 0;
        }
        else if(StrEqual(info, "info"))
        {
            ShowInfoMenu(client);
            return 0;
        }
        
        ShowSettingsMenu(client);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
    
    return 0;
}

void ShowQuestionTypesMenu(int client)
{
    Menu menu = new Menu(MenuHandler_QuestionTypes);
    menu.SetTitle("Question Types\n \nSelect which types of questions you want:");
    
    char typeValue[16];
    GetClientCookie(client, g_hCookieQuestionTypes, typeValue, sizeof(typeValue));
    int types = StringToInt(typeValue);
    
    char display[64];
    bool mathEnabled = (types & (1 << view_as<int>(TYPE_MATH))) != 0;
    bool scienceEnabled = (types & (1 << view_as<int>(TYPE_SCIENCE))) != 0;
    bool programmingEnabled = (types & (1 << view_as<int>(TYPE_PROGRAMMING))) != 0;
    bool generalEnabled = (types & (1 << view_as<int>(TYPE_GENERAL))) != 0;
    
    Format(display, sizeof(display), "Math Questions: %s", mathEnabled ? "{green}✓" : "{red}✗");
    StripColors(display, display, sizeof(display));
    menu.AddItem("math", display);
    
    Format(display, sizeof(display), "Science Questions: %s", scienceEnabled ? "{green}✓" : "{red}✗");
    StripColors(display, display, sizeof(display));
    menu.AddItem("science", display);
    
    Format(display, sizeof(display), "Programming Questions: %s", programmingEnabled ? "{green}✓" : "{red}✗");
    StripColors(display, display, sizeof(display));
    menu.AddItem("programming", display);
    
    Format(display, sizeof(display), "General Questions: %s", generalEnabled ? "{green}✓" : "{red}✗");
    StripColors(display, display, sizeof(display));
    menu.AddItem("general", display);
    
    menu.AddItem("all", "Select All Types");
    menu.AddItem("none", "Deselect All Types");
    menu.AddItem("back", "Back to Settings");
    
    menu.ExitButton = true;
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_QuestionTypes(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        char typeValue[16];
        GetClientCookie(client, g_hCookieQuestionTypes, typeValue, sizeof(typeValue));
        int types = StringToInt(typeValue);
        
        if(StrEqual(info, "math"))
        {
            types ^= (1 << view_as<int>(TYPE_MATH));
        }
        else if(StrEqual(info, "science"))
        {
            types ^= (1 << view_as<int>(TYPE_SCIENCE));
        }
        else if(StrEqual(info, "programming"))
        {
            types ^= (1 << view_as<int>(TYPE_PROGRAMMING));
        }
        else if(StrEqual(info, "general"))
        {
            types ^= (1 << view_as<int>(TYPE_GENERAL));
        }
        else if(StrEqual(info, "all"))
        {
            types = 15; // 1+2+4+8 = 15 (all types)
        }
        else if(StrEqual(info, "none"))
        {
            types = 0;
        }
        else if(StrEqual(info, "back"))
        {
            ShowSettingsMenu(client);
            return 0;
        }
        
        IntToString(types, typeValue, sizeof(typeValue));
        SetClientCookie(client, g_hCookieQuestionTypes, typeValue);
        
        ShowQuestionTypesMenu(client);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
    else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowSettingsMenu(client);
    }
    
    return 0;
}

void ShowInfoMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Info);
    menu.SetTitle("Quiz Information\n \nAbout Random Quiz:\n \n");
    
    menu.AddItem("line1", "• Questions appear every 2-3 minutes", ITEMDRAW_DISABLED);
    menu.AddItem("line2", "• Four modes: Chat & Menu, Menu Only,", ITEMDRAW_DISABLED);
    menu.AddItem("line3", "  Chat Only, or Disabled", ITEMDRAW_DISABLED);
    menu.AddItem("line4", "• Earn credits for correct answers", ITEMDRAW_DISABLED);
    menu.AddItem("line5", "• Difficulty affects reward amount", ITEMDRAW_DISABLED);
    menu.AddItem("line6", "• Math questions are auto-generated", ITEMDRAW_DISABLED);
    menu.AddItem("line7", "• Other questions from config file", ITEMDRAW_DISABLED);
    menu.AddItem("line8", "• Filter question types in settings", ITEMDRAW_DISABLED);
    
    menu.AddItem("back", "Back to Settings");
    
    menu.ExitButton = true;
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Info(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "back"))
        {
            ShowSettingsMenu(client);
        }
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
    else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
    {
        ShowSettingsMenu(client);
    }
    
    return 0;
}

public void OnMapStart()
{
    StopCurrentQuestion();
    g_iQuestionCounter = 0;
    g_arrScienceQuestions.Clear();
    g_arrProgrammingQuestions.Clear();
    g_arrGeneralQuestions.Clear();
    g_arrMathQuestions.Clear();
    g_bConfigLoaded = false;
    
    char configPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, configPath, sizeof(configPath), CONFIG_PATH);
    
    if(FileExists(configPath))
    {
        LoadConfigQuestions(configPath);
    }
    else
    {
        LogMessage("Config file not found: %s", configPath);
    }
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsClientConnected(i))
        {
            g_iAttempts[i] = 0;
            g_iMenuPlayersAnswered[i] = 0;
        }
    }
}

void LoadConfigQuestions(const char[] configPath)
{
    KeyValues kv = new KeyValues("Questions");
    
    if(!kv.ImportFromFile(configPath))
    {
        LogError("Failed to load questions config: %s", configPath);
        delete kv;
        return;
    }
    
    ConfigQuestion qData;
    
    // Load science questions
    if(kv.JumpToKey("science"))
    {
        if(kv.GotoFirstSubKey())
        {
            do
            {
                kv.GetString("question", qData.question, sizeof(qData.question));
                kv.GetString("answer", qData.answer, sizeof(qData.answer));
                qData.difficulty = kv.GetNum("difficulty", DIFFICULTY_MEDIUM);
                
                if(strlen(qData.question) > 0 && strlen(qData.answer) > 0)
                {
                    g_arrScienceQuestions.PushArray(qData);
                }
            }
            while(kv.GotoNextKey());
            kv.GoBack();
        }
        kv.GoBack();
    }
    
    // Load programming questions
    if(kv.JumpToKey("programming"))
    {
        if(kv.GotoFirstSubKey())
        {
            do
            {
                kv.GetString("question", qData.question, sizeof(qData.question));
                kv.GetString("answer", qData.answer, sizeof(qData.answer));
                qData.difficulty = kv.GetNum("difficulty", DIFFICULTY_MEDIUM);
                
                if(strlen(qData.question) > 0 && strlen(qData.answer) > 0)
                {
                    g_arrProgrammingQuestions.PushArray(qData);
                }
            }
            while(kv.GotoNextKey());
            kv.GoBack();
        }
        kv.GoBack();
    }
    
    // Load general questions
    if(kv.JumpToKey("general"))
    {
        if(kv.GotoFirstSubKey())
        {
            do
            {
                kv.GetString("question", qData.question, sizeof(qData.question));
                kv.GetString("answer", qData.answer, sizeof(qData.answer));
                qData.difficulty = kv.GetNum("difficulty", DIFFICULTY_MEDIUM);
                
                if(strlen(qData.question) > 0 && strlen(qData.answer) > 0)
                {
                    g_arrGeneralQuestions.PushArray(qData);
                }
            }
            while(kv.GotoNextKey());
            kv.GoBack();
        }
        kv.GoBack();
    }
    
    delete kv;
    g_bConfigLoaded = true;
    
    if(g_cvDebugMode.BoolValue)
    {
        PrintToServer("[RandomQuiz] Loaded %d science, %d programming, %d general questions from config",
                     g_arrScienceQuestions.Length, g_arrProgrammingQuestions.Length, g_arrGeneralQuestions.Length);
    }
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    StopCurrentQuestion();
    g_iQuestionCounter = 0;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i) && IsQuizEnabledForClient(i))
        {
            CPrintToChat(i, "{aqua}[Quiz]{default} You can customize quiz settings using {lightblue}/quizsettings{default} command.");
        }
    }
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsClientConnected(i))
        {
            g_iAttempts[i] = 0;
            g_iMenuPlayersAnswered[i] = 0;
        }
    }
    
    if(g_cvEnabled.BoolValue)
    {
        CreateTimer(10.0, Timer_StartFirstQuestion, _, TIMER_FLAG_NO_MAPCHANGE);
        
        if(g_cvDebugMode.BoolValue)
        {
            PrintToServer("[RandomQuiz] Round started - first question in 10 seconds");
        }
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    StopCurrentQuestion();
    
    if(g_cvDebugMode.BoolValue)
    {
        PrintToServer("[RandomQuiz] Round ended - questions stopped");
    }
}

public void OnClientPutInServer(int client)
{
    if(!IsClientConnected(client) || IsFakeClient(client))
        return;
    
    g_iAttempts[client] = 0;
    g_iMenuPlayersAnswered[client] = 0;
}

public Action Timer_StartFirstQuestion(Handle timer)
{
    if(g_cvEnabled.BoolValue)
    {
        StartNewQuestion();
    }
    return Plugin_Stop;
}

bool IsQuizEnabledForClient(int client)
{
    if(!IsClientInGame(client) || !IsClientConnected(client) || IsFakeClient(client))
        return false;
    
    char enabledValue[16];
    GetClientCookie(client, g_hCookieEnabled, enabledValue, sizeof(enabledValue));
    return StringToInt(enabledValue) != 0;
}

bool ShouldSeeChatQuestions(int client)
{
    if(!IsQuizEnabledForClient(client))
        return false;
    
    char chatOnlyValue[16], menuOnlyValue[16];
    GetClientCookie(client, g_hCookieChatOnly, chatOnlyValue, sizeof(chatOnlyValue));
    GetClientCookie(client, g_hCookieMenuOnly, menuOnlyValue, sizeof(menuOnlyValue));
    
    if(StringToInt(menuOnlyValue) != 0)
        return false;
    
    return true;
}

bool ShouldSeeMenuQuestions(int client)
{
    if(!IsQuizEnabledForClient(client))
        return false;
    
    char chatOnlyValue[16], menuOnlyValue[16];
    GetClientCookie(client, g_hCookieChatOnly, chatOnlyValue, sizeof(chatOnlyValue));
    GetClientCookie(client, g_hCookieMenuOnly, menuOnlyValue, sizeof(menuOnlyValue));
    
    if(StringToInt(chatOnlyValue) != 0)
        return false;
    
    return true;
}

bool IsQuestionTypeEnabledForClient(int client, QuestionType qType)
{
    if(!IsQuizEnabledForClient(client))
        return false;
    
    char typeValue[16];
    GetClientCookie(client, g_hCookieQuestionTypes, typeValue, sizeof(typeValue));
    int types = StringToInt(typeValue);
    
    return (types & (1 << view_as<int>(qType))) != 0;
}

QuestionType GetRandomQuestionTypeForClient(int client, bool forMenu = false)
{
    int availableTypes = 0;
    QuestionType typeList[TYPE_COUNT];
    
    for(QuestionType qType = TYPE_MATH; qType < TYPE_COUNT; qType++)
    {
        if(IsQuestionTypeEnabledForClient(client, qType))
        {
            bool hasQuestions = false;
            switch(qType)
            {
                case TYPE_MATH:
                    hasQuestions = true;
                case TYPE_SCIENCE:
                    hasQuestions = g_arrScienceQuestions.Length > 0;
                case TYPE_PROGRAMMING:
                    hasQuestions = g_arrProgrammingQuestions.Length > 0;
                case TYPE_GENERAL:
                    hasQuestions = g_arrGeneralQuestions.Length > 0;
            }
            
            if(hasQuestions)
            {
                typeList[availableTypes] = qType;
                availableTypes++;
            }
        }
    }
    
    if(availableTypes == 0)
        return TYPE_MATH;
    
    if(forMenu && availableTypes > 1)
    {
        ArrayList weightedList = new ArrayList();
        
        for(int i = 0; i < availableTypes; i++)
        {
            if(typeList[i] != TYPE_MATH)
            {
                weightedList.Push(typeList[i]);
                weightedList.Push(typeList[i]);
            }
            else
            {
                weightedList.Push(typeList[i]);
            }
        }
        
        int randomIndex = GetRandomInt(0, weightedList.Length - 1);
        QuestionType selectedType = weightedList.Get(randomIndex);
        delete weightedList;
        
        return selectedType;
    }
    
    return typeList[GetRandomInt(0, availableTypes - 1)];
}

void StartNewQuestion()
{
    if(!g_cvEnabled.BoolValue)
        return;
    
    StopCurrentQuestion();
    g_bQuestionAnswered = false;
    g_iCorrectClient = -1;
    g_fTimeout = GetGameTime() + g_cvTimeout.FloatValue;
    g_sCurrentAnswer[0] = '\0';
    g_sCurrentQuestion[0] = '\0';
    g_iCurrentReward = 0;
    g_iCurrentDifficulty = DIFFICULTY_MEDIUM;
    g_bMenuQuestion = false;
    g_iMenuCorrectIndex = -1;
    g_iCurrentQuestionType = TYPE_MATH;
    
    for(int i = 0; i < 6; i++)
    {
        g_sMenuAnswers[i][0] = '\0';
    }
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsClientConnected(i))
        {
            g_iAttempts[i] = 0;
            g_iMenuPlayersAnswered[i] = 0;
        }
    }
    
    int[] clients = new int[MaxClients];
    int clientCount = 0;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i) && IsQuizEnabledForClient(i))
        {
            clients[clientCount++] = i;
        }
    }
    
    if(clientCount == 0)
    {
        QuestionMode qMode = GetRandomQuestionMode();
        
        if(qMode == MODE_MENU)
        {
            if(!GenerateConfigQuestion())
                GenerateMathQuestion();
        }
        else
        {
            QuestionType qType;
            int random = GetRandomInt(1, 100);
            
            if(random <= 70)
            {
                qType = TYPE_MATH;
            }
            else
            {
                ArrayList availableTypes = new ArrayList();
                if(g_arrScienceQuestions.Length > 0) availableTypes.Push(TYPE_SCIENCE);
                if(g_arrProgrammingQuestions.Length > 0) availableTypes.Push(TYPE_PROGRAMMING);
                if(g_arrGeneralQuestions.Length > 0) availableTypes.Push(TYPE_GENERAL);
                
                if(availableTypes.Length == 0)
                {
                    qType = TYPE_MATH;
                }
                else
                {
                    int typeIndex = GetRandomInt(0, availableTypes.Length - 1);
                    qType = availableTypes.Get(typeIndex);
                }
                delete availableTypes;
            }
            
            switch(qType)
            {
                case TYPE_MATH: GenerateMathQuestion();
                case TYPE_SCIENCE: if(!GenerateScienceQuestion()) GenerateMathQuestion();
                case TYPE_PROGRAMMING: if(!GenerateProgrammingQuestion()) GenerateMathQuestion();
                case TYPE_GENERAL: if(!GenerateGeneralQuestion()) GenerateMathQuestion();
            }
        }
    }
    else
    {
        int randomClient = clients[GetRandomInt(0, clientCount - 1)];
        
        QuestionMode qMode = GetRandomQuestionMode();
        g_iCurrentQuestionType = GetRandomQuestionTypeForClient(randomClient, qMode == MODE_MENU);
        
        if(qMode == MODE_MENU)
        {
            bool questionGenerated = false;
            switch(g_iCurrentQuestionType)
            {
                case TYPE_SCIENCE:
                    questionGenerated = GenerateScienceQuestion();
                case TYPE_PROGRAMMING:
                    questionGenerated = GenerateProgrammingQuestion();
                case TYPE_GENERAL:
                    questionGenerated = GenerateGeneralQuestion();
                default:
                    questionGenerated = GenerateMathQuestion();
            }
            
            if(!questionGenerated)
                GenerateMathQuestion();
        }
        else
        {
            switch(g_iCurrentQuestionType)
            {
                case TYPE_MATH:
                    GenerateMathQuestion();
                case TYPE_SCIENCE:
                    if(!GenerateScienceQuestion()) GenerateMathQuestion();
                case TYPE_PROGRAMMING:
                    if(!GenerateProgrammingQuestion()) GenerateMathQuestion();
                case TYPE_GENERAL:
                    if(!GenerateGeneralQuestion()) GenerateMathQuestion();
            }
        }
    }
    
    g_iCurrentReward = CalculateReward(g_iCurrentDifficulty);
    g_iQuestionCounter++;
    
    QuestionMode finalMode = GetRandomQuestionMode();
    if(finalMode == MODE_MENU && PrepareMenuQuestion())
    {
        g_bMenuQuestion = true;
        g_fTimeout = GetGameTime() + g_cvMaxMenuTime.FloatValue;
    }
    else
    {
        g_bMenuQuestion = false;
    }
    
    if(g_cvDebugMode.BoolValue)
    {
        char typeNames[TYPE_COUNT][16] = {"Math", "Science", "Programming", "General"};
        PrintToServer("[RandomQuiz] Question #%d: Type: %s | Mode: %s | Answer: %s | Difficulty: %d | Reward: %d", 
                     g_iQuestionCounter, typeNames[g_iCurrentQuestionType], 
                     g_bMenuQuestion ? "Menu" : "Chat", g_sCurrentAnswer, 
                     g_iCurrentDifficulty, g_iCurrentReward);
    }
    
    DisplayQuestionToPlayers();
    
    float timeout = g_bMenuQuestion ? g_cvMaxMenuTime.FloatValue : g_cvTimeout.FloatValue;
    g_hTimeoutTimer = CreateTimer(timeout, Timer_QuestionTimeout, _, TIMER_FLAG_NO_MAPCHANGE);
}

/*
QuestionType GetRandomQuestionType(bool forMenu = false)
{
    if(forMenu)
    {
        int availableCategories = 0;
        if(g_arrScienceQuestions.Length > 0) availableCategories++;
        if(g_arrProgrammingQuestions.Length > 0) availableCategories++;
        if(g_arrGeneralQuestions.Length > 0) availableCategories++;
        
        if(availableCategories == 0)
            return TYPE_MATH;
        
        int categoryIndex = GetRandomInt(1, availableCategories);
        int currentCategory = 0;
        
        if(g_arrScienceQuestions.Length > 0)
        {
            currentCategory++;
            if(currentCategory == categoryIndex) return TYPE_SCIENCE;
        }
        
        if(g_arrProgrammingQuestions.Length > 0)
        {
            currentCategory++;
            if(currentCategory == categoryIndex) return TYPE_PROGRAMMING;
        }
        
        if(g_arrGeneralQuestions.Length > 0)
        {
            currentCategory++;
            if(currentCategory == categoryIndex) return TYPE_GENERAL;
        }
        
        return TYPE_MATH;
    }
    
    int random = GetRandomInt(1, 100);
    
    if(random <= 70) 
        return TYPE_MATH;
    
    int availableCategories = 1;
    
    if(g_arrScienceQuestions.Length > 0) availableCategories++;
    if(g_arrProgrammingQuestions.Length > 0) availableCategories++;
    if(g_arrGeneralQuestions.Length > 0) availableCategories++;
    
    int nonMathCategories = availableCategories - 1;
    
    if(nonMathCategories > 0)
    {
        int categoryIndex = GetRandomInt(1, nonMathCategories);
        int currentCategory = 0;
        
        if(g_arrScienceQuestions.Length > 0)
        {
            currentCategory++;
            if(currentCategory == categoryIndex) return TYPE_SCIENCE;
        }
        
        if(g_arrProgrammingQuestions.Length > 0)
        {
            currentCategory++;
            if(currentCategory == categoryIndex) return TYPE_PROGRAMMING;
        }
        
        if(g_arrGeneralQuestions.Length > 0)
        {
            currentCategory++;
            if(currentCategory == categoryIndex) return TYPE_GENERAL;
        }
    }
    
    return TYPE_MATH;
}
*/

bool GenerateConfigQuestion()
{
    ArrayList availableTypes = new ArrayList();
    
    if(g_arrScienceQuestions.Length > 0) availableTypes.Push(TYPE_SCIENCE);
    if(g_arrProgrammingQuestions.Length > 0) availableTypes.Push(TYPE_PROGRAMMING);
    if(g_arrGeneralQuestions.Length > 0) availableTypes.Push(TYPE_GENERAL);
    
    if(availableTypes.Length == 0)
        return false;
    
    int randomIndex = GetRandomInt(0, availableTypes.Length - 1);
    QuestionType selectedType = availableTypes.Get(randomIndex);
    delete availableTypes;
    
    switch(selectedType)
    {
        case TYPE_SCIENCE: return GenerateScienceQuestion();
        case TYPE_PROGRAMMING: return GenerateProgrammingQuestion();
        case TYPE_GENERAL: return GenerateGeneralQuestion();
    }
    
    return false;
}

QuestionMode GetRandomQuestionMode()
{
    int chatPlayers = 0;
    int menuPlayers = 0;
    int allPlayers = 0;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i))
        {
            char enabledValue[16], chatOnlyValue[16], menuOnlyValue[16];
            GetClientCookie(i, g_hCookieEnabled, enabledValue, sizeof(enabledValue));
            GetClientCookie(i, g_hCookieChatOnly, chatOnlyValue, sizeof(chatOnlyValue));
            GetClientCookie(i, g_hCookieMenuOnly, menuOnlyValue, sizeof(menuOnlyValue));
            
            if(StringToInt(enabledValue) != 0)
            {
                allPlayers++;
                
                if(StringToInt(chatOnlyValue) != 0)
                    chatPlayers++;
                else if(StringToInt(menuOnlyValue) != 0)
                    menuPlayers++;
                else
                {
                    chatPlayers++;
                    menuPlayers++;
                }
            }
        }
    }
    
    if(allPlayers == 0)
        return MODE_CHAT;
    
    if(chatPlayers > 0 && menuPlayers == 0)
        return MODE_CHAT;
    
    if(menuPlayers > 0 && chatPlayers == 0)
        return MODE_MENU;
    
    int random = GetRandomInt(1, 100);
    if(random <= g_cvMenuPercentage.IntValue)
    {
        return MODE_MENU;
    }
    
    return MODE_CHAT;
}

int CalculateReward(int difficulty)
{
    int minCredits = g_cvMinCredits.IntValue;
    int maxCredits = g_cvMaxCredits.IntValue;
    
    if(minCredits > maxCredits)
    {
        int temp = minCredits;
        minCredits = maxCredits;
        maxCredits = temp;
    }
    
    int range = maxCredits - minCredits;

    if(range <= 0)
        return minCredits;
    
    int reward;
    
    switch(difficulty)
    {
        case DIFFICULTY_EASY:
            reward = GetRandomInt(minCredits, minCredits + (range / 3));
            
        case DIFFICULTY_MEDIUM:
            reward = GetRandomInt(minCredits + (range / 3), 
                                 minCredits + ((range * 2) / 3));
            
        case DIFFICULTY_HARD:
            reward = GetRandomInt(minCredits + ((range * 2) / 3), maxCredits);
            
        default:
            reward = GetRandomInt(minCredits, maxCredits);
    }
    
    if(reward < minCredits)
        reward = minCredits;
    if(reward > maxCredits)
        reward = maxCredits;
        
    return reward;
}

char[] GetDifficultyName(int difficulty)
{
    static char name[16];
    switch(difficulty)
    {
        case DIFFICULTY_EASY: name = "Easy";
        case DIFFICULTY_MEDIUM: name = "Medium";
        case DIFFICULTY_HARD: name = "Hard";
        default: name = "Medium";
    }
    return name;
}

char[] GetQuestionTypeName(QuestionType qType)
{
    static char name[16];
    switch(qType)
    {
        case TYPE_MATH: name = "Math";
        case TYPE_SCIENCE: name = "Science";
        case TYPE_PROGRAMMING: name = "Programming";
        case TYPE_GENERAL: name = "General";
        default: name = "Unknown";
    }
    return name;
}

void ProcessCorrectAnswer(int client)
{
    if(g_bQuestionAnswered)
    {
        if(IsQuizEnabledForClient(client))
        {
            CPrintToChat(client, "{aqua}[Quiz]{default} Someone already answered this question!");
        }
        return;
    }
    
    if(!IsQuizEnabledForClient(client))
        return;
    
    g_iCorrectClient = client;
    g_bQuestionAnswered = true;
    
    if(g_hTimeoutTimer != null)
    {
        KillTimer(g_hTimeoutTimer);
        g_hTimeoutTimer = null;
    }

    if(g_bMenuQuestion && g_iMenuPlayersAnswered[client] == 2)
    {
        CPrintToChat(client, "{aqua}[Quiz]{default} You cannot answer - you already answered wrong!");
        return;
    }
    
    float penalty = 0.2 * (g_iAttempts[client] - 1);
    if(penalty > 0.5) penalty = 0.5;
    
    int finalReward = RoundToCeil(float(g_iCurrentReward) * (1.0 - penalty));
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i) && IsQuizEnabledForClient(i))
        {
            if(Shop_IsAuthorized(client))
            {
                CPrintToChat(i, "{lightblue}[Quiz]{default} {green}%N{default} answered correctly! {orange}+%d credits{default} | Type: {olive}%s", 
                          client, finalReward, GetQuestionTypeName(g_iCurrentQuestionType));
            }
            else
            {
                CPrintToChat(i, "{lightblue}[Quiz]{default} {green}%N{default} answered correctly! (No Shop) | Type: {olive}%s", 
                          client, GetQuestionTypeName(g_iCurrentQuestionType));
            }
        }
    }
    
    if(Shop_IsAuthorized(client))
    {
        Shop_GiveClientCredits(client, finalReward);
    }
    
    g_hQuestionTimer = CreateTimer(g_cvQuestionInterval.FloatValue, Timer_NextQuestion, _, TIMER_FLAG_NO_MAPCHANGE);
}

void DisplayQuestionToPlayers()
{
    char difficultyColor[32];
    char rewardColor[32];
    char typeColor[32];
    
    switch(g_iCurrentDifficulty)
    {
        case DIFFICULTY_EASY:
        {
            Format(difficultyColor, sizeof(difficultyColor), "{olive}");
            Format(rewardColor, sizeof(rewardColor), "{olive}");
        }
        case DIFFICULTY_MEDIUM:
        {
            Format(difficultyColor, sizeof(difficultyColor), "{orange}");
            Format(rewardColor, sizeof(rewardColor), "{orange}");
        }
        case DIFFICULTY_HARD:
        {
            Format(difficultyColor, sizeof(difficultyColor), "{fullred}");
            Format(rewardColor, sizeof(rewardColor), "{fullred}");
        }
        default:
        {
            Format(difficultyColor, sizeof(difficultyColor), "{orange}");
            Format(rewardColor, sizeof(rewardColor), "{orange}");
        }
    }
    
    switch(g_iCurrentQuestionType)
    {
        case TYPE_MATH: Format(typeColor, sizeof(typeColor), "{lightblue}");
        case TYPE_SCIENCE: Format(typeColor, sizeof(typeColor), "{lime}");
        case TYPE_PROGRAMMING: Format(typeColor, sizeof(typeColor), "{magenta}");
        case TYPE_GENERAL: Format(typeColor, sizeof(typeColor), "{yellow}");
        default: Format(typeColor, sizeof(typeColor), "{white}");
    }
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientInGame(i) || !IsClientConnected(i) || IsFakeClient(i))
            continue;
            
        if(!IsQuizEnabledForClient(i))
            continue;
            
        if(!IsQuestionTypeEnabledForClient(i, g_iCurrentQuestionType))
        {
            continue;
        }
        
        if(g_bMenuQuestion)
        {
            if(ShouldSeeMenuQuestions(i))
            {
                ShowQuestionMenu(i);
            }
        }
        else
        {
            if(ShouldSeeChatQuestions(i))
            {
                CPrintToChat(i, "{aqua}[Quiz]{default} Question {lightblue}#%d{default}: {magenta}%s", 
                           g_iQuestionCounter, g_sCurrentQuestion);
                CPrintToChat(i, "{aqua}[Quiz]{default} Type: %s%s{default} | Difficulty: %s%s{default} | Reward: %s%d credits", 
                           typeColor, GetQuestionTypeName(g_iCurrentQuestionType),
                           difficultyColor, GetDifficultyName(g_iCurrentDifficulty), 
                           rewardColor, g_iCurrentReward);
                CPrintToChat(i, "{aqua}[Quiz]{default} Time: {fullred}%.0f{default}s | Type your answer in chat!", 
                           g_cvTimeout.FloatValue);
            }
        }
    }
}

void ShowQuestionMenu(int client)
{
    if(!g_bMenuQuestion || g_iMenuCorrectIndex == -1)
        return;
    
    Menu dummy = new Menu(MenuHandler_Dummy);
    dummy.Display(client, 0);
    delete dummy;
    
    char cleanQuestion[256];
    Menu menu = new Menu(MenuHandler_Question);
    StripColors(g_sCurrentQuestion, cleanQuestion, sizeof(cleanQuestion));
    
    char typeColor[32];
    switch(g_iCurrentQuestionType)
    {
        case TYPE_MATH: Format(typeColor, sizeof(typeColor), "{lightblue}");
        case TYPE_SCIENCE: Format(typeColor, sizeof(typeColor), "{lime}");
        case TYPE_PROGRAMMING: Format(typeColor, sizeof(typeColor), "{magenta}");
        case TYPE_GENERAL: Format(typeColor, sizeof(typeColor), "{yellow}");
        default: Format(typeColor, sizeof(typeColor), "{white}");
    }
    
    char coloredType[64];
    Format(coloredType, sizeof(coloredType), "%s%s", typeColor, GetQuestionTypeName(g_iCurrentQuestionType));
    StripColors(coloredType, coloredType, sizeof(coloredType));
    
    menu.SetTitle("Quiz Question #%d\n \n%s\n \nType: %s | Difficulty: %s\nReward: %d credits\nTime: %.0fs\n \n", 
             g_iQuestionCounter, cleanQuestion, coloredType,
             GetDifficultyName(g_iCurrentDifficulty), g_iCurrentReward,
             g_fTimeout - GetGameTime());
    
    int options = g_cvMenuOptions.IntValue;
    if(options > 6) options = 6;
    
    for(int i = 0; i < options; i++)
    {
        if(strlen(g_sMenuAnswers[i]) > 0)
        {
            char display[256];
            char cleanAnswer[256];
            StripColors(g_sMenuAnswers[i], cleanAnswer, sizeof(cleanAnswer));
            
            Format(display, sizeof(display), "%d. %s", i + 1, cleanAnswer);
            
            char info[16];
            Format(info, sizeof(info), "%d", i);
            menu.AddItem(info, display);
        }
    }
    menu.AddItem("exit", "0. Exit / Close Menu", ITEMDRAW_DEFAULT);
    
    menu.ExitButton = true;
    menu.Display(client, RoundToCeil(g_fTimeout - GetGameTime()));
}

public int MenuHandler_Dummy(Menu menu, MenuAction action, int client, int param2)
{
    return 0;
}

public int MenuHandler_Question(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        if(GetGameTime() > g_fTimeout)
        {
            if(IsQuizEnabledForClient(client))
            {
                CPrintToChat(client, "{aqua}[Quiz]{default} Time's up! Question has expired.");
            }
            return 0;
        }
        
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "exit"))
        {
            if(IsQuizEnabledForClient(client))
            {
                CPrintToChat(client, "{aqua}[Quiz]{default} Menu closed. Question is still active!");
            }
            return 0;
        }
        
        int selectedIndex = StringToInt(info);
        if(g_bQuestionAnswered || g_iCorrectClient != -1)
        {
            if(IsQuizEnabledForClient(client))
            {
                CPrintToChat(client, "{aqua}[Quiz]{default} Someone already answered this question!");
            }
            return 0;
        }
        
        if(!IsQuizEnabledForClient(client))
            return 0;
            
        if(g_iMenuPlayersAnswered[client] > 0)
        {
            CPrintToChat(client, "{aqua}[Quiz]{default} You already answered this question!");
            return 0;
        }
        
        if(selectedIndex == g_iMenuCorrectIndex)
        {
            g_iMenuPlayersAnswered[client] = 1;
            ProcessCorrectAnswer(client);
        }
        else
        {
            CPrintToChat(client, "{aqua}[Quiz]{default} Wrong answer! You cannot answer this question anymore.");
            g_iMenuPlayersAnswered[client] = 2;
        }
    }
    else if(action == MenuAction_Cancel)
    {
        if(param2 == MenuCancel_Exit || param2 == MenuCancel_Timeout)
        {
            if(param2 == MenuCancel_Exit && IsQuizEnabledForClient(client))
            {
                CPrintToChat(client, "{aqua}[Quiz]{default} Menu closed. Question is still active!");
            }
        }
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
    
    return 0;
}

void StripColors(const char[] input, char[] output, int maxlen)
{
    int len = strlen(input);
    int pos = 0;
    
    for(int i = 0; i < len && pos < maxlen - 1; i++)
    {
        if(input[i] == '{')
        {
            int j = i + 1;
            while(j < len && input[j] != '}' && j < i + 32)
                j++;
            
            if(j < len && input[j] == '}')
                i = j;
            else
                output[pos++] = input[i];
        }
        else
        {
            output[pos++] = input[i];
        }
    }
    output[pos] = '\0';
}

bool PrepareMenuQuestion()
{
    int options = g_cvMenuOptions.IntValue;
    if(options > 6) options = 6;
    if(options < 2) options = 2;
    
    for(int i = 0; i < 6; i++)
    {
        g_sMenuAnswers[i][0] = '\0';
    }
    
    strcopy(g_sMenuAnswers[0], sizeof(g_sMenuAnswers[]), g_sCurrentAnswer);
    g_iMenuCorrectIndex = 0;
    
    for(int i = 1; i < options; i++)
    {
        GenerateWrongAnswer(i);
    }
    
    for(int i = 0; i < options * 2; i++)
    {
        int idx1 = GetRandomInt(0, options - 1);
        int idx2 = GetRandomInt(0, options - 1);
        
        if(idx1 != idx2)
        {
            char temp[128];
            strcopy(temp, sizeof(temp), g_sMenuAnswers[idx1]);
            strcopy(g_sMenuAnswers[idx1], sizeof(g_sMenuAnswers[]), g_sMenuAnswers[idx2]);
            strcopy(g_sMenuAnswers[idx2], sizeof(g_sMenuAnswers[]), temp);
            
            if(idx1 == g_iMenuCorrectIndex)
                g_iMenuCorrectIndex = idx2;
            else if(idx2 == g_iMenuCorrectIndex)
                g_iMenuCorrectIndex = idx1;
        }
    }
    
    return true;
}

void GenerateWrongAnswer(int index)
{
    if(IsStringNumeric(g_sCurrentAnswer))
    {
        int correctNum = StringToInt(g_sCurrentAnswer);
        int wrongNum;
        int attempts = 0;
        
        do
        {
            int offset;
            if(correctNum == 0)
            {
                offset = GetRandomInt(-10, 10);
                if(offset == 0) offset = GetRandomInt(1, 5);
            }
            else
            {
                int percentage = GetRandomInt(10, 50);
                if(GetRandomInt(0, 1) == 0)
                    percentage = -percentage;
                    
                offset = RoundToCeil(float(correctNum) * (float(percentage) / 100.0));
                if(offset == 0) offset = GetRandomInt(1, 5);
            }
            
            wrongNum = correctNum + offset;
            attempts++;
            
        } while((wrongNum == correctNum || IsDuplicateAnswer(wrongNum, index)) && attempts < 10);
        
        IntToString(wrongNum, g_sMenuAnswers[index], sizeof(g_sMenuAnswers[]));
    }
    else
    {
        char wrong[128];
        int strategy = GetRandomInt(0, 3);
        
        switch(strategy)
        {
            case 0: // Random similar answer
            {
                if(StrContains(g_sCurrentQuestion, "capital", false) != -1)
                {
                    char capitals[][] = {"London", "Paris", "Berlin", "Madrid", "Rome", "Tokyo", "Washington", "Beijing", "Moscow", "Canberra"};
                    do
                    {
                        Format(wrong, sizeof(wrong), "%s", capitals[GetRandomInt(0, sizeof(capitals) - 1)]);
                    } while(StrEqual(wrong, g_sCurrentAnswer));
                }
                else if(StrContains(g_sCurrentQuestion, "chemical", false) != -1)
                {
                    char chemicals[][] = {"H2O", "CO2", "O2", "NaCl", "CH4", "NH3", "H2SO4", "C6H12O6", "HCl", "NaOH"};
                    do
                    {
                        Format(wrong, sizeof(wrong), "%s", chemicals[GetRandomInt(0, sizeof(chemicals) - 1)]);
                    } while(StrEqual(wrong, g_sCurrentAnswer));
                }
                else
                {
                    Format(wrong, sizeof(wrong), "Answer %c", GetRandomInt('A', 'Z'));
                }
            }
            case 1: // Modify the correct answer
            {
                strcopy(wrong, sizeof(wrong), g_sCurrentAnswer);
                int len = strlen(wrong);
                
                if(len > 2)
                {
                    if(GetRandomInt(0, 1) == 0 && len < sizeof(wrong) - 1)
                    {
                        // Add a character
                        int pos = GetRandomInt(0, len);
                        for(int i = len; i > pos; i--)
                            wrong[i] = wrong[i - 1];
                        wrong[pos] = GetRandomInt('a', 'z');
                        if(GetRandomInt(0, 3) == 0)
                            wrong[pos] = CharToUpper(wrong[pos]);
                        wrong[len + 1] = '\0';
                    }
                    else
                    {
                        // Remove a character
                        int pos = GetRandomInt(0, len - 1);
                        for(int i = pos; i < len; i++)
                            wrong[i] = wrong[i + 1];
                    }
                }
            }
            case 2: // Random letters
            {
                int len = strlen(g_sCurrentAnswer);
                if(len > 10) len = 10;
                
                for(int i = 0; i < len; i++)
                {
                    wrong[i] = GetRandomInt('a', 'z');
                    if(GetRandomInt(0, 3) == 0)
                        wrong[i] = CharToUpper(wrong[i]);
                }
                wrong[len] = '\0';
            }
            case 3: // Common wrong answers
            {
                if(StrContains(g_sCurrentAnswer, "Au", false) != -1)
                    Format(wrong, sizeof(wrong), "Ag");
                else if(StrContains(g_sCurrentAnswer, "Ag", false) != -1)
                    Format(wrong, sizeof(wrong), "Au");
                else if(StrContains(g_sCurrentAnswer, "Paris", false) != -1)
                    Format(wrong, sizeof(wrong), "London");
                else if(StrContains(g_sCurrentAnswer, "Tokyo", false) != -1)
                    Format(wrong, sizeof(wrong), "Beijing");
                else
                    Format(wrong, sizeof(wrong), "Wrong %d", GetRandomInt(1, 999));
            }
        }
        
        int attempts = 0;
        while((StrEqual(wrong, g_sCurrentAnswer) || IsDuplicateAnswerString(wrong, index)) && attempts < 10)
        {
            Format(wrong, sizeof(wrong), "Option %d", GetRandomInt(1, 999));
            attempts++;
        }
        
        strcopy(g_sMenuAnswers[index], sizeof(g_sMenuAnswers[]), wrong);
    }
}

bool IsStringNumeric(const char[] str)
{
    int len = strlen(str);
    if(len == 0) return false;
    
    int start = 0;
    if(str[0] == '-') start = 1;
    
    for(int i = start; i < len; i++)
    {
        if(!IsCharNumeric(str[i]))
            return false;
    }
    return true;
}

bool IsDuplicateAnswer(int number, int currentIndex)
{
    for(int i = 0; i < currentIndex; i++)
    {
        if(IsStringNumeric(g_sMenuAnswers[i]))
        {
            if(StringToInt(g_sMenuAnswers[i]) == number)
                return true;
        }
    }
    return false;
}

bool IsDuplicateAnswerString(const char[] answer, int currentIndex)
{
    for(int i = 0; i < currentIndex; i++)
    {
        if(StrEqual(g_sMenuAnswers[i], answer))
            return true;
    }
    return false;
}

char[] GetNumberSuffix(int number)
{
    static char suffix[4];
    
    if(number % 10 == 1 && number % 100 != 11)
        Format(suffix, sizeof(suffix), "st");
    else if(number % 10 == 2 && number % 100 != 12)
        Format(suffix, sizeof(suffix), "nd");
    else if(number % 10 == 3 && number % 100 != 13)
        Format(suffix, sizeof(suffix), "rd");
    else
        Format(suffix, sizeof(suffix), "th");
    
    return suffix;
}

bool GenerateMathQuestion()
{
    g_iCurrentQuestionType = TYPE_MATH;
    int minNum = g_cvMinNumber.IntValue;
    int maxNum = g_cvMaxNumber.IntValue;
    
    int operation = GetRandomInt(0, 7);
    
    switch(operation)
    {
        case 0: // Simple addition
        {
            int num1 = GetRandomInt(minNum, maxNum/2);
            int num2 = GetRandomInt(minNum, maxNum/2);
            int answer = num1 + num2;
            IntToString(answer, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
            Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), "What is {orange}%d + %d{default}?", num1, num2);
            g_iCurrentDifficulty = DIFFICULTY_EASY;
            return true;
        }
        case 1: // Simple subtraction
        {
            int num1 = GetRandomInt(minNum, maxNum);
            int num2 = GetRandomInt(minNum, num1);
            int answer = num1 - num2;
            IntToString(answer, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
            Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), "What is {orange}%d - %d{default}?", num1, num2);
            g_iCurrentDifficulty = DIFFICULTY_EASY;
            return true;
        }
        case 2: // Simple multiplication
        {
            int num1 = GetRandomInt(2, 20);
            int num2 = GetRandomInt(2, 20);
            int answer = num1 * num2;
            IntToString(answer, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
            Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), "What is {orange}%d × %d{default}?", num1, num2);
            g_iCurrentDifficulty = DIFFICULTY_EASY;
            return true;
        }
        case 3: // Simple division
        {
            int divisor = GetRandomInt(2, 12);
            int result = GetRandomInt(2, 20);
            int dividend = divisor * result;
            IntToString(result, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
            Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), "What is {orange}%d ÷ %d{default}?", dividend, divisor);
            g_iCurrentDifficulty = DIFFICULTY_EASY;
            return true;
        }
        case 4: // Find nth even/odd number
        {
            bool even = GetRandomInt(0, 1) == 1;
            int nth = GetRandomInt(3, 8);
            int start = GetRandomInt(1, 20);
            
            if(even && start % 2 != 0) start++;
            if(!even && start % 2 == 0) start++;
            
            int answer = start + ((nth - 1) * 2);
            IntToString(answer, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
            Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), 
                   "What is the {orange}%d%s %s number{default} starting from {orange}%d{default}?", 
                   nth, GetNumberSuffix(nth), even ? "even" : "odd", start);
            g_iCurrentDifficulty = DIFFICULTY_MEDIUM;
            return true;
        }
        case 5: // Multiple operations
        {
            int num1 = GetRandomInt(10, 50);
            int num2 = GetRandomInt(10, 50);
            int num3 = GetRandomInt(2, 10);
            
            if(GetRandomInt(0, 1) == 0)
            {
                // (a + b) × c
                int answer = (num1 + num2) * num3;
                IntToString(answer, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
                Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), 
                       "What is ({orange}%d + %d{default}) × {orange}%d{default}?", num1, num2, num3);
            }
            else
            {
                // a × b + c
                int answer = (num1 * num2) + num3;
                IntToString(answer, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
                Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), 
                       "What is {orange}%d × %d + %d{default}?", num1, num2, num3);
            }
            g_iCurrentDifficulty = DIFFICULTY_MEDIUM;
            return true;
        }
        case 6: // Square root
        {
            int num = GetRandomInt(2, 15);
            int answer = num * num;
            IntToString(num, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
            Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), 
                   "What is the square root of {orange}%d{default}?", answer);
            g_iCurrentDifficulty = DIFFICULTY_MEDIUM;
            return true;
        }
        case 7: // Percentage
        {
            int num = GetRandomInt(10, 200);
            int percent = GetRandomInt(10, 90);
            int answer = RoundToCeil(float(num) * (float(percent) / 100.0));
            IntToString(answer, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
            Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), 
                   "What is {orange}%d%%{default} of {orange}%d{default}?", percent, num);
            g_iCurrentDifficulty = DIFFICULTY_HARD;
            return true;
        }
    }
    
    int num1 = GetRandomInt(minNum, maxNum/2);
    int num2 = GetRandomInt(minNum, maxNum/2);
    int answer = num1 + num2;
    IntToString(answer, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
    Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), "What is {orange}%d + %d{default}?", num1, num2);
    g_iCurrentDifficulty = DIFFICULTY_EASY;
    return true;
}

bool GenerateScienceQuestion()
{
    if(g_arrScienceQuestions.Length == 0)
        return false;
    
    g_iCurrentQuestionType = TYPE_SCIENCE;
    int index = GetRandomInt(0, g_arrScienceQuestions.Length - 1);
    ConfigQuestion qData;
    g_arrScienceQuestions.GetArray(index, qData);
    
    strcopy(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), qData.question);
    strcopy(g_sCurrentAnswer, sizeof(g_sCurrentAnswer), qData.answer);
    g_iCurrentDifficulty = qData.difficulty;
    
    return true;
}

bool GenerateProgrammingQuestion()
{
    if(g_arrProgrammingQuestions.Length == 0)
        return false;
    
    g_iCurrentQuestionType = TYPE_PROGRAMMING;
    int index = GetRandomInt(0, g_arrProgrammingQuestions.Length - 1);
    ConfigQuestion qData;
    g_arrProgrammingQuestions.GetArray(index, qData);
    
    strcopy(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), qData.question);
    strcopy(g_sCurrentAnswer, sizeof(g_sCurrentAnswer), qData.answer);
    g_iCurrentDifficulty = qData.difficulty;
    
    return true;
}

bool GenerateGeneralQuestion()
{
    if(g_arrGeneralQuestions.Length == 0)
        return false;
    
    g_iCurrentQuestionType = TYPE_GENERAL;
    int index = GetRandomInt(0, g_arrGeneralQuestions.Length - 1);
    ConfigQuestion qData;
    g_arrGeneralQuestions.GetArray(index, qData);
    
    strcopy(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), qData.question);
    strcopy(g_sCurrentAnswer, sizeof(g_sCurrentAnswer), qData.answer);
    g_iCurrentDifficulty = qData.difficulty;
    
    return true;
}

void StopCurrentQuestion()
{
    if(g_hQuestionTimer != null)
    {
        KillTimer(g_hQuestionTimer);
        g_hQuestionTimer = null;
    }
    
    if(g_hTimeoutTimer != null)
    {
        KillTimer(g_hTimeoutTimer);
        g_hTimeoutTimer = null;
    }
}

public Action Timer_QuestionTimeout(Handle timer)
{
    g_hTimeoutTimer = null; 
    
    if(!g_bQuestionAnswered && g_iCorrectClient == -1)
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientInGame(i) && IsClientConnected(i) && !IsFakeClient(i) && IsQuizEnabledForClient(i))
            {
                CPrintToChat(i, "{lightblue}[Quiz]{default} Time's up! No one answered. Type: {olive}%s", 
                          GetQuestionTypeName(g_iCurrentQuestionType));
            }
        }
    }
    
    // Close all open menus
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsClientConnected(i))
        {
            Menu dummy = new Menu(MenuHandler_Dummy);
            dummy.Display(i, 0);
            delete dummy;
        }
    }
    
    g_bQuestionAnswered = false;
    g_hQuestionTimer = CreateTimer(g_cvQuestionInterval.FloatValue, Timer_NextQuestion, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_NextQuestion(Handle timer)
{
    g_hQuestionTimer = null;
    StartNewQuestion();
    return Plugin_Stop;
}

public Action Command_Say(int client, const char[] command, int argc)
{
    if(!g_cvEnabled.BoolValue || !IsClientInGame(client) || !IsClientConnected(client) || IsFakeClient(client) || IsChatTrigger())
        return Plugin_Continue;

    char text[256];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);
    
    if(StrEqual(text, ""))
        return Plugin_Continue;
    
    if(StrContains(text, "!") == 0 || StrContains(text, "/") == 0)
        return Plugin_Continue;
    
    if(!IsQuizEnabledForClient(client))
        return Plugin_Continue;
    
    if(g_iCorrectClient != -1 || GetGameTime() > g_fTimeout)
    {
        return Plugin_Continue;
    }
    
    if(g_bQuestionAnswered || g_iCorrectClient != -1)
    {
        if(IsQuizEnabledForClient(client))
        {
            CPrintToChat(client, "{lightblue}[Quiz]{default} Someone already answered this question!");
        }
        return Plugin_Continue;
    }
    
    if(!ShouldSeeChatQuestions(client))
    {
        CPrintToChat(client, "{aqua}[Quiz]{default} You're in {orange}Menu Only{default} mode! Change to {aqua}Chat & Menu{default} or {lime}Chat Only{default} in {orange}/quizmenu{default} to answer in chat.");
        return Plugin_Continue;
    }
    
    if(!IsQuestionTypeEnabledForClient(client, g_iCurrentQuestionType))
    {
        // Don't show any message for disabled question types
        return Plugin_Continue;
    }
    
    if(g_iAttempts[client] >= g_cvMaxAttempts.IntValue)
    {
        if(IsQuizEnabledForClient(client))
        {
            CPrintToChat(client, "{lightblue}[Quiz]{default} You've used all {red}%d{default} attempts!", g_cvMaxAttempts.IntValue);
        }
        return Plugin_Continue;
    }
    
    if(g_bMenuQuestion && g_iMenuPlayersAnswered[client] == 2)
    {
        if(IsQuizEnabledForClient(client))
        {
            CPrintToChat(client, "{aqua}[Quiz]{default} You already answered wrong in menu!");
        }
        return Plugin_Continue;
    }
    
    char lowerAnswer[128];
    char lowerText[256];
    
    strcopy(lowerAnswer, sizeof(lowerAnswer), g_sCurrentAnswer);
    strcopy(lowerText, sizeof(lowerText), text);
    
    if(!g_cvAllowCaseSensitive.BoolValue)
    {
        StringToLower(lowerAnswer);
        StringToLower(lowerText);
    }
    
    g_iAttempts[client]++;
    bool correct = false;
    
    if(StrEqual(lowerText, lowerAnswer, false))
    {
        correct = true;
    }
    else
    {
        char answerNum[32];
        if(ExtractNumber(g_sCurrentAnswer, answerNum, sizeof(answerNum)))
        {
            if(StrEqual(text, answerNum, false))
                correct = true;
        }
    }
    
    if(correct)
    {
        ProcessCorrectAnswer(client);
    }
    else
    {
        if(IsQuizEnabledForClient(client))
        {
            int attemptsLeft = g_cvMaxAttempts.IntValue - g_iAttempts[client];
            CPrintToChat(client, "{lightblue}[Quiz]{default} Wrong answer! Attempts left: {red}%d", attemptsLeft);
        }
    }
    
    return Plugin_Continue;
}

bool ExtractNumber(const char[] input, char[] output, int maxlen)
{
    int len = strlen(input);
    int pos = 0;
    
    for(int i = 0; i < len && pos < maxlen - 1; i++)
    {
        if(IsCharNumeric(input[i]) || (input[i] == '-' && pos == 0))
        {
            output[pos++] = input[i];
        }
    }
    
    output[pos] = '\0';
    return pos > 0;
}

void StringToLower(char[] str)
{
    int length = strlen(str);
    for(int i = 0; i < length; i++)
    {
        str[i] = CharToLower(str[i]);
    }
}