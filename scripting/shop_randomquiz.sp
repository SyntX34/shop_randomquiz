#pragma semicolon 1
#include <sourcemod>
#include <shop>
#include <multicolors>
#include <sdktools>
#include <keyvalues>
#include <clientprefs>

#pragma newdecls required

#define PLUGIN_NAME "Random Quiz"
#define PLUGIN_VERSION "5.0.1"
#define CONFIG_PATH "configs/random_quiz/questions.cfg"

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
char g_sMenuAnswers[4][128];
int g_iMenuCorrectIndex = -1;
int g_iMenuPlayersAnswered[MAXPLAYERS+1];

ArrayList g_arrScienceQuestions;
ArrayList g_arrProgrammingQuestions;
ArrayList g_arrGeneralQuestions;
bool g_bConfigLoaded = false;
bool g_bQuestionAnswered = false;

Handle g_hCookieEnabled;
Handle g_hCookieMenuOnly;

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
    g_cvMinCredits = CreateConVar("sm_randomquiz_mincredits", "50", "Minimum credits reward", _, true, 10.0);
    g_cvMaxCredits = CreateConVar("sm_randomquiz_maxcredits", "500", "Maximum credits reward", _, true, 100.0);
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
    
    SetCookieMenuItem(CookieMenuHandler_QuizSettings, 0, "Quiz Settings");
    g_arrScienceQuestions = new ArrayList(sizeof(ConfigQuestion));
    g_arrProgrammingQuestions = new ArrayList(sizeof(ConfigQuestion));
    g_arrGeneralQuestions = new ArrayList(sizeof(ConfigQuestion));
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            g_iAttempts[i] = 0;
            g_iMenuPlayersAnswered[i] = 0;
            
            if(AreClientCookiesCached(i))
            {
                char value[8];
                GetClientCookie(i, g_hCookieEnabled, value, sizeof(value));
                if(strlen(value) == 0)
                {
                    SetClientCookie(i, g_hCookieEnabled, "1");
                }
                
                GetClientCookie(i, g_hCookieMenuOnly, value, sizeof(value));
                if(strlen(value) == 0)
                {
                    SetClientCookie(i, g_hCookieMenuOnly, "0");
                }
            }
        }
    }
}

public void OnClientCookiesCached(int client)
{
    char value[8];
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
    
    char enabledValue[8], menuOnlyValue[8];
    GetClientCookie(client, g_hCookieEnabled, enabledValue, sizeof(enabledValue));
    GetClientCookie(client, g_hCookieMenuOnly, menuOnlyValue, sizeof(menuOnlyValue));
    
    bool isEnabled = StringToInt(enabledValue) != 0;
    bool menuOnly = StringToInt(menuOnlyValue) != 0;
    
    char display[64];
    char cleanDisplay[64];
    Format(display, sizeof(display), "Quiz: %s", isEnabled ? "{green}Enabled" : "{red}Disabled");
    StripColors(display, cleanDisplay, sizeof(cleanDisplay));
    menu.AddItem("toggle", cleanDisplay);
    
    Format(display, sizeof(display), "Question Mode: %s", menuOnly ? "{orange}Menu Only" : "{aqua}Chat & Menu");
    StripColors(display, cleanDisplay, sizeof(cleanDisplay));
    menu.AddItem("mode", cleanDisplay);

    menu.AddItem("info", "Information & Help");
    
    menu.ExitButton = true;
    menu.ExitBackButton = false;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Settings(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "toggle"))
        {
            char value[8];
            GetClientCookie(client, g_hCookieEnabled, value, sizeof(value));
            bool isEnabled = StringToInt(value) != 0;
            
            SetClientCookie(client, g_hCookieEnabled, isEnabled ? "0" : "1");
            
            if(isEnabled)
            {
                CPrintToChat(client, "{aqua}[Quiz]{default} You have {red}disabled{default} quiz questions.");
            }
            else
            {
                CPrintToChat(client, "{aqua}[Quiz]{default} You have {green}enabled{default} quiz questions.");
            }
        }
        else if(StrEqual(info, "mode"))
        {
            char value[8];
            GetClientCookie(client, g_hCookieMenuOnly, value, sizeof(value));
            bool menuOnly = StringToInt(value) != 0;
            
            SetClientCookie(client, g_hCookieMenuOnly, menuOnly ? "0" : "1");
            
            if(menuOnly)
            {
                CPrintToChat(client, "{aqua}[Quiz]{default} You will now see {aqua}both chat and menu{default} questions.");
            }
            else
            {
                CPrintToChat(client, "{aqua}[Quiz]{default} You will now see {orange}only menu{default} questions.");
            }
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

void ShowInfoMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Info);
    menu.SetTitle("Quiz Information\n \nAbout Random Quiz:\n \n");
    
    menu.AddItem("line1", "• Questions appear every 2-3 minutes", ITEMDRAW_DISABLED);
    menu.AddItem("line2", "• Answer in chat or select menu option", ITEMDRAW_DISABLED);
    menu.AddItem("line3", "• Earn credits for correct answers", ITEMDRAW_DISABLED);
    menu.AddItem("line4", "• Difficulty affects reward amount", ITEMDRAW_DISABLED);
    menu.AddItem("line5", "• Math questions are auto-generated", ITEMDRAW_DISABLED);
    menu.AddItem("line6", "• Other questions from config file", ITEMDRAW_DISABLED);
    
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

bool IsQuizEnabledForClient(int client)
{
    if(!IsClientInGame(client) || IsFakeClient(client))
        return false;
    
    char value[8];
    GetClientCookie(client, g_hCookieEnabled, value, sizeof(value));
    return StringToInt(value) != 0;
}

bool IsMenuOnlyForClient(int client)
{
    char value[8];
    GetClientCookie(client, g_hCookieMenuOnly, value, sizeof(value));
    return StringToInt(value) != 0;
}

public void OnMapStart()
{
    StopCurrentQuestion();
    g_iQuestionCounter = 0;
    g_arrScienceQuestions.Clear();
    g_arrProgrammingQuestions.Clear();
    g_arrGeneralQuestions.Clear();
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
        g_iAttempts[i] = 0;
        g_iMenuPlayersAnswered[i] = 0;
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
        g_iAttempts[i] = 0;
        g_iMenuPlayersAnswered[i] = 0;
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
    
    for(int i = 0; i < 4; i++)
    {
        g_sMenuAnswers[i][0] = '\0';
    }
    
    for(int i = 1; i <= MaxClients; i++)
    {
        g_iAttempts[i] = 0;
        g_iMenuPlayersAnswered[i] = 0;
    }
    
    QuestionMode qMode = GetRandomQuestionMode();
    
    bool questionGenerated = false;
    
    if(qMode == MODE_MENU)
    {
        QuestionType qType = GetRandomQuestionType(true);
        
        switch(qType)
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
    }
    else
    {
        QuestionType qType = GetRandomQuestionType(false);
        
        switch(qType)
        {
            case TYPE_MATH:
                questionGenerated = GenerateMathQuestion();
            case TYPE_SCIENCE:
                questionGenerated = GenerateScienceQuestion();
            case TYPE_PROGRAMMING:
                questionGenerated = GenerateProgrammingQuestion();
            case TYPE_GENERAL:
                questionGenerated = GenerateGeneralQuestion();
        }
    }
    
    if(!questionGenerated || g_sCurrentAnswer[0] == '\0')
    {
        GenerateMathQuestion();
    }
    
    g_iCurrentReward = CalculateReward(g_iCurrentDifficulty);
    g_iQuestionCounter++;
    
    if(qMode == MODE_MENU && PrepareMenuQuestion())
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
        PrintToServer("[RandomQuiz] Question #%d: %s | Answer: %s | Difficulty: %d | Reward: %d | Mode: %s", 
                     g_iQuestionCounter, g_sCurrentQuestion, g_sCurrentAnswer, 
                     g_iCurrentDifficulty, g_iCurrentReward, g_bMenuQuestion ? "Menu" : "Chat");
    }
    
    DisplayQuestionToPlayers();
    
    float timeout = g_bMenuQuestion ? g_cvMaxMenuTime.FloatValue : g_cvTimeout.FloatValue;
    g_hTimeoutTimer = CreateTimer(timeout, Timer_QuestionTimeout, _, TIMER_FLAG_NO_MAPCHANGE);
}

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

int CalculateReward(int difficulty)
{
    int minCredits = g_cvMinCredits.IntValue;
    int maxCredits = g_cvMaxCredits.IntValue;
    
    switch(difficulty)
    {
        case DIFFICULTY_EASY:
            return GetRandomInt(minCredits, minCredits + ((maxCredits - minCredits) / 3));
        case DIFFICULTY_MEDIUM:
            return GetRandomInt(minCredits + ((maxCredits - minCredits) / 3), 
                              minCredits + ((maxCredits - minCredits) * 2 / 3));
        case DIFFICULTY_HARD:
            return GetRandomInt(minCredits + ((maxCredits - minCredits) * 2 / 3), maxCredits);
        default:
            return GetRandomInt(minCredits, maxCredits);
    }
}

char[] GetDifficultyName(int difficulty)
{
    char name[16];
    switch(difficulty)
    {
        case DIFFICULTY_EASY: name = "Easy";
        case DIFFICULTY_MEDIUM: name = "Medium";
        case DIFFICULTY_HARD: name = "Hard";
        default: name = "Medium";
    }
    return name;
}

void ProcessCorrectAnswer(int client)
{
    if(g_bQuestionAnswered)
    {
        CPrintToChat(client, "{aqua}[Quiz]{default} Someone already answered this question!");
        return;
    }
    g_iCorrectClient = client;
    g_bQuestionAnswered = true;
    
    if(g_hTimeoutTimer != null)
    {
        KillTimer(g_hTimeoutTimer);
        g_hTimeoutTimer = null;
    }

    if(g_iMenuPlayersAnswered[client] == 2)
    {
        CPrintToChat(client, "{aqua}[Quiz]{default} You cannot answer - you already answered wrong!");
        return;
    }
    
    // Calculate reward with penalty for attempts
    float penalty = 0.2 * (g_iAttempts[client] - 1);
    if(penalty > 0.5) penalty = 0.5;
    
    int finalReward = RoundToCeil(float(g_iCurrentReward) * (1.0 - penalty));
    
    if(Shop_IsAuthorized(client))
    {
        Shop_GiveClientCredits(client, finalReward);
        CPrintToChatAll("{lightblue}[Quiz]{default} {green}%N{default} answered correctly! {orange}+%d credits{default} | Answer: {orange}%s", 
                      client, finalReward, g_sCurrentAnswer);
    }
    else
    {
        CPrintToChatAll("{lightblue}[Quiz]{default} {green}%N{default} answered correctly! (No Shop) | Answer: {orange}%s", 
                      client, g_sCurrentAnswer);
    }
    
    g_hQuestionTimer = CreateTimer(g_cvQuestionInterval.FloatValue, Timer_NextQuestion, _, TIMER_FLAG_NO_MAPCHANGE);
}

QuestionMode GetRandomQuestionMode()
{
    bool anyMenuOnly = false;
    int enabledPlayers = 0;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && !IsFakeClient(i) && IsQuizEnabledForClient(i))
        {
            enabledPlayers++;
            if(IsMenuOnlyForClient(i))
            {
                anyMenuOnly = true;
            }
        }
    }
    if(anyMenuOnly && enabledPlayers > 0)
    {
        return MODE_MENU;
    }
    int random = GetRandomInt(1, 100);
    if(random <= g_cvMenuPercentage.IntValue)
    {
        return MODE_MENU;
    }
    
    return MODE_CHAT;
}

void DisplayQuestionToPlayers()
{
    char difficultyColor[32];
    char rewardColor[32];
    
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
    
    // Display to all players
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && !IsFakeClient(i) && IsQuizEnabledForClient(i))
        {
            if(g_bMenuQuestion)
            {
                // Show menu question
                ShowQuestionMenu(i);
            }
            else
            {
                // Show chat question
                CPrintToChat(i, "{aqua}[Quiz]{default} Question {lightblue}#%d{default}: {magenta}%s", 
                           g_iQuestionCounter, g_sCurrentQuestion);
                CPrintToChat(i, "{aqua}[Quiz]{default} Time: {fullred}%.0f{default}s | Difficulty: %s%s{default} | Reward: %s%d credits", 
                           g_cvTimeout.FloatValue, difficultyColor, GetDifficultyName(g_iCurrentDifficulty), rewardColor, g_iCurrentReward);
                CPrintToChat(i, "{aqua}[Quiz]{default} Type your answer in chat! {olive}(/quizmenu to disable)");
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
    menu.SetTitle("Quiz Question #%d\n \n%s\n \nDifficulty: %s\nReward: %d credits\nTime: %.0fs\n \n", 
             g_iQuestionCounter, cleanQuestion, 
             GetDifficultyName(g_iCurrentDifficulty), g_iCurrentReward,
             g_fTimeout - GetGameTime());
    
    int options = g_cvMenuOptions.IntValue;
    if(options > 4) options = 4;
    
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
            CPrintToChat(client, "{aqua}[Quiz]{default} Time's up! Question has expired.");
            return 0;
        }
        
        char info[16];
        menu.GetItem(param2, info, sizeof(info));
        
        if(StrEqual(info, "exit"))
        {
            CPrintToChat(client, "{aqua}[Quiz]{default} Menu closed. Question is still active!");
            return 0;
        }
        
        int selectedIndex = StringToInt(info);
        if(g_bQuestionAnswered || g_iCorrectClient != -1)
        {
            CPrintToChat(client, "{aqua}[Quiz]{default} Someone already answered this question!");
            return 0;
        }
        
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
            if(param2 == MenuCancel_Exit)
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
    if(options > 4) options = 4;
    if(options < 2) options = 2;
    
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
        
        do
        {
            int offset = GetRandomInt(-10, 10);
            if(offset == 0) offset = GetRandomInt(1, 5);
            wrongNum = correctNum + offset;
            
        } while(wrongNum == correctNum || IsDuplicateAnswer(wrongNum, index));
        
        IntToString(wrongNum, g_sMenuAnswers[index], sizeof(g_sMenuAnswers[]));
    }
    else
    {
    
        char wrong[128];
        
        int strategy = GetRandomInt(0, 2);
        
        switch(strategy)
        {
            case 0: 
            {
                int len = strlen(g_sCurrentAnswer);
                for(int i = 0; i < len; i++)
                {
                    wrong[i] = GetRandomInt('a', 'z');
                    if(GetRandomInt(0, 3) == 0)
                        wrong[i] = CharToUpper(wrong[i]);
                }
                wrong[len] = '\0';
            }
            case 1:
            {
                strcopy(wrong, sizeof(wrong), g_sCurrentAnswer);
                int len = strlen(wrong);
                
                if(len > 3 && GetRandomInt(0, 1) == 0)
                {
                    
                    int pos = GetRandomInt(0, len - 1);
                    for(int i = pos; i < len; i++)
                        wrong[i] = wrong[i + 1];
                }
                else
                {
                    
                    if(len < sizeof(wrong) - 1)
                    {
                        int pos = GetRandomInt(0, len);
                        for(int i = len; i > pos; i--)
                            wrong[i] = wrong[i - 1];
                        wrong[pos] = GetRandomInt('a', 'z');
                        if(GetRandomInt(0, 3) == 0)
                            wrong[pos] = CharToUpper(wrong[pos]);
                        wrong[len + 1] = '\0';
                    }
                }
            }
            case 2:
            {
                if(StrContains(g_sCurrentQuestion, "capital", false) != -1)
                {
                    char capitals[][] = {"London", "Paris", "Berlin", "Madrid", "Rome", "Tokyo"};
                    Format(wrong, sizeof(wrong), "%s", capitals[GetRandomInt(0, sizeof(capitals) - 1)]);
                }
                else if(StrContains(g_sCurrentQuestion, "chemical", false) != -1)
                {
                    char chemicals[][] = {"H2O", "CO2", "O2", "NaCl", "CH4", "NH3"};
                    Format(wrong, sizeof(wrong), "%s", chemicals[GetRandomInt(0, sizeof(chemicals) - 1)]);
                }
                else
                {
                    Format(wrong, sizeof(wrong), "Answer %d", index + 1);
                }
            }
        }
    
        int attempts = 0;
        while((StrEqual(wrong, g_sCurrentAnswer) || IsDuplicateAnswerString(wrong, index)) && attempts < 10)
        {
            Format(wrong, sizeof(wrong), "Wrong %d", GetRandomInt(100, 999));
            attempts++;
        }
        
        strcopy(g_sMenuAnswers[index], sizeof(g_sMenuAnswers[]), wrong);
    }
}

bool IsStringNumeric(const char[] str)
{
    int len = strlen(str);
    for(int i = 0; i < len; i++)
    {
        if(!IsCharNumeric(str[i]) && str[i] != '-')
            return false;
    }
    return len > 0;
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
    char suffix[4] = "";
    
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
    int minNum = g_cvMinNumber.IntValue;
    int maxNum = g_cvMaxNumber.IntValue;
    
    int operation = GetRandomInt(0, 5);
    
    switch(operation)
    {
        case 0: // Simple addition
        {
            int num1 = GetRandomInt(minNum, maxNum/2);
            int num2 = GetRandomInt(minNum, maxNum/2);
            int answer = num1 + num2;
            IntToString(answer, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
            Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), "What is {orange}%d + %d{default}?", num1, num2);
            return true;
        }
        case 1: // Simple subtraction
        {
            int num1 = GetRandomInt(minNum, maxNum);
            int num2 = GetRandomInt(minNum, num1);
            int answer = num1 - num2;
            IntToString(answer, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
            Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), "What is {orange}%d - %d{default}?", num1, num2);
            return true;
        }
        case 2: // Simple multiplication
        {
            int num1 = GetRandomInt(2, 20);
            int num2 = GetRandomInt(2, 20);
            int answer = num1 * num2;
            IntToString(answer, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
            Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), "What is {orange}%d × %d{default}?", num1, num2);
            return true;
        }
        case 3: // Simple division
        {
            int divisor = GetRandomInt(2, 12);
            int result = GetRandomInt(2, 20);
            int dividend = divisor * result;
            IntToString(result, g_sCurrentAnswer, sizeof(g_sCurrentAnswer));
            Format(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), "What is {orange}%d ÷ %d{default}?", dividend, divisor);
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
            return true;
        }
    }
    
    return false;
}

bool GenerateScienceQuestion()
{
    if(g_arrScienceQuestions.Length == 0)
        return false;
    
    int index = GetRandomInt(0, g_arrScienceQuestions.Length - 1);
    ConfigQuestion qData;
    g_arrScienceQuestions.GetArray(index, qData);
    
    strcopy(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), qData.question);
    strcopy(g_sCurrentAnswer, sizeof(g_sCurrentAnswer), qData.answer);
    
    return true;
}

bool GenerateProgrammingQuestion()
{
    if(g_arrProgrammingQuestions.Length == 0)
        return false;
    
    int index = GetRandomInt(0, g_arrProgrammingQuestions.Length - 1);
    ConfigQuestion qData;
    g_arrProgrammingQuestions.GetArray(index, qData);
    
    strcopy(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), qData.question);
    strcopy(g_sCurrentAnswer, sizeof(g_sCurrentAnswer), qData.answer);
    
    return true;
}

bool GenerateGeneralQuestion()
{
    if(g_arrGeneralQuestions.Length == 0)
        return false;
    
    int index = GetRandomInt(0, g_arrGeneralQuestions.Length - 1);
    ConfigQuestion qData;
    g_arrGeneralQuestions.GetArray(index, qData);
    
    strcopy(g_sCurrentQuestion, sizeof(g_sCurrentQuestion), qData.question);
    strcopy(g_sCurrentAnswer, sizeof(g_sCurrentAnswer), qData.answer);
    
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
        CPrintToChatAll("{lightblue}[Quiz]{default} Time's up! No one answered. Answer was: {orange}%s", g_sCurrentAnswer);
    }
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && !IsFakeClient(i))
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
    if(!g_cvEnabled.BoolValue || !IsClientInGame(client) || IsChatTrigger() || 
       g_iCorrectClient != -1 || GetGameTime() > g_fTimeout)
        return Plugin_Continue;

    if(GetGameTime() > g_fTimeout)
    {
        char text[256];
        GetCmdArgString(text, sizeof(text));
        StripQuotes(text);
        TrimString(text);
        
        if(StrContains(text, "!") != 0 && StrContains(text, "/") != 0)
        {
            CPrintToChat(client, "{aqua}[Quiz]{default} Time's up! Question has expired.");
        }
        return Plugin_Continue;
    }

    if(g_bQuestionAnswered || g_iCorrectClient != -1)
    {
        CPrintToChat(client, "{lightblue}[Quiz]{default} Someone already answered this question!");
        return Plugin_Continue;
    }
    
    if(g_iAttempts[client] >= g_cvMaxAttempts.IntValue)
    {
        CPrintToChat(client, "{lightblue}[Quiz]{default} You've used all {red}%d{default} attempts!", g_cvMaxAttempts.IntValue);
        return Plugin_Continue;
    }

    if(g_iMenuPlayersAnswered[client] == 2)
    {
        CPrintToChat(client, "{aqua}[Quiz]{default} You already answered wrong in menu!");
        return Plugin_Continue;
    }
    
    char text[256];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);
    TrimString(text);
    
    if(StrEqual(text, ""))
        return Plugin_Continue;
    
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
        int attemptsLeft = g_cvMaxAttempts.IntValue - g_iAttempts[client];
        CPrintToChat(client, "{lightblue}[Quiz]{default} Wrong answer! Attempts left: {red}%d", attemptsLeft);
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