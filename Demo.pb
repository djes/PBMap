; ********************************************************************
; Program:           PBMap example
; Author:            djes
; Date:              Jan, 2021
; License:           PBMap : Free, unrestricted, credit 
;                    appreciated but not required.
; OSM :              see http://www.openstreetmap.org/copyright
; Note:              Please share improvement !
; Thanks:            Progi1984, falsam
; ********************************************************************
;
; Track bugs with the following options with debugger enabled
;    PBMap::SetOption(#Map, "ShowDebugInfos", "1")
;    PBMap::SetDebugLevel(5)
;    PBMap::SetOption(#Map, "Verbose", "1")
;
; or with the OnError() PB capabilities :
;    
; CompilerIf #PB_Compiler_LineNumbering = #False
;     MessageRequester("Warning !", "You must enable 'OnError lines support' in compiler options", #PB_MessageRequester_Ok )
;   End
; CompilerEndIf 
; 
; Declare ErrorHandler()
; 
; OnErrorCall(@ErrorHandler())
; 
; Procedure ErrorHandler()
;   MessageRequester("Ooops", "The following error happened : " + ErrorMessage(ErrorCode()) + #CRLF$ +"line : " +  Str(ErrorLine()))
; EndProcedure
;
; ******************************************************************** 

XIncludeFile "PBMap.pb"

InitNetwork()

CompilerIf #PB_Compiler_Thread = #False
  MessageRequester("Warning !", "You must enable 'Create ThreadSafe Executable' in compiler options", #PB_MessageRequester_Ok )
  End
CompilerEndIf 

EnableExplicit

Enumeration
  #Window_0
  #Map
  #Gdt_Left
  #Gdt_Right
  #Gdt_Up
  #Gdt_Down
  ; #Gdt_RotateLeft
  ; #Gdt_RotateRight
  #Button_4
  #Button_5
  #Combo_0
  #Text_0
  #Text_1
  #Text_2
  #Text_3
  #Text_4
  #StringLatitude
  #StringLongitude
  #Gdt_LoadGpx
  #Gdt_SaveGpx
  #Gdt_AddMarker
  #Gdt_AddOpenseaMap
  #Gdt_AddHereMap
  #Gdt_AddGeoServerMap
  #Gdt_Degrees
  #Gdt_EditMode 
  #Gdt_ClearDiskCache
  #TextGeoLocationQuery
  #StringGeoLocationQuery
EndEnumeration

; Menu events
Enumeration
  #MenuEventLonLatStringEnter
  #MenuEventGeoLocationStringEnter
EndEnumeration

Structure Location
  Longitude.d
  Latitude.d
EndStructure

Procedure UpdateLocation(*Location.Location)
  SetGadgetText(#StringLatitude, StrD(*Location\Latitude))
  SetGadgetText(#StringLongitude, StrD(*Location\Longitude))
  ProcedureReturn 0
EndProcedure

; This callback demonstration procedure will receive relative coords from canvas
Procedure MyMarker(x.i, y.i, Focus = #False, Selected = #False)
  Protected color = RGBA(0, 255, 0, 255) 
  MovePathCursor(x, y)
  AddPathLine(-16,-32,#PB_Path_Relative)
  AddPathCircle(16,0,16,180,0,#PB_Path_Relative)
  AddPathLine(-16,32,#PB_Path_Relative)
  VectorSourceColor(color)
  FillPath(#PB_Path_Preserve)
  If Focus
    VectorSourceColor(RGBA($FF, $FF, 0, $FF))
    StrokePath(2)
  ElseIf Selected
    VectorSourceColor(RGBA($FF, $FF, 0, $FF))
    StrokePath(3)
  Else
    VectorSourceColor(RGBA(0, 0, 0, 255))
    StrokePath(1)
  EndIf
EndProcedure

Procedure MarkerMoveCallBack(*Marker.PBMap::Marker)
  Debug "Identifier : " + *Marker\Identifier + "(" + StrD(*Marker\GeographicCoordinates\Latitude) + ", " + StrD(*Marker\GeographicCoordinates\Longitude) + ")"
EndProcedure

; Example of a custom procedure to alter tile rendering
Procedure DrawTileCallBack(x.i, y.i, image.i, alpha.d)
  MovePathCursor(x, y)
  DrawVectorImage(ImageID(image), 255 * alpha)
EndProcedure

; Example of a custom procedure to alter tile file just after loading
Procedure.s ModifyTileFileCallback(CacheFile.s, OrgURL.s)
  Protected ImgNB = LoadImage(#PB_Any, CacheFile)
  If ImgNB
    StartDrawing(ImageOutput(ImgNB))
    DrawText(0, 0,"PUREBASIC", RGB(255, 255, 0))
    StopDrawing()
    ;*** Could be used to create new files
    ; Cachefile = ReplaceString(Cachefile, ".png", "_PB.png") 
    ;***
    If SaveImage(ImgNB, CacheFile, #PB_ImagePlugin_PNG, 0, 32) ;Warning, the 32 is mandatory as some tiles aren't correctly rendered
                                                               ; Send back the new name (not functional by now)
      ProcedureReturn CacheFile
    EndIf
  EndIf
EndProcedure

Procedure MainPointer(x.i, y.i)
  VectorSourceColor(RGBA(255, 255,255, 255)) : AddPathCircle(x, y,32) : StrokePath(1)
  VectorSourceColor(RGBA(0, 0, 0, 255)) : AddPathCircle(x, y, 29):StrokePath(2)
EndProcedure

Procedure ResizeAll()
  ResizeGadget(#Map, 10, 10, WindowWidth(#Window_0)-198, WindowHeight(#Window_0)-59)
  ResizeGadget(#Text_1, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_Left, WindowWidth(#Window_0) - 150, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_Right, WindowWidth(#Window_0) -  90, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ; ResizeGadget(#Gdt_RotateLeft, WindowWidth(#Window_0) - 150, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ; ResizeGadget(#Gdt_RotateRight, WindowWidth(#Window_0) -  90, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_Up,   WindowWidth(#Window_0) - 120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_Down, WindowWidth(#Window_0) - 120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Text_2, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Button_4, WindowWidth(#Window_0)-150, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Button_5, WindowWidth(#Window_0)-100, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Text_3, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#StringLatitude, WindowWidth(#Window_0)-120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#StringLongitude, WindowWidth(#Window_0)-120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Text_4, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_AddMarker, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_LoadGpx, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_SaveGpx, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_AddOpenseaMap, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_AddHereMap, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_AddGeoServerMap, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_Degrees, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_EditMode, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_ClearDiskCache, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#TextGeoLocationQuery, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#StringGeoLocationQuery, WindowWidth(#Window_0)-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  PBMap::Refresh(#Map)
EndProcedure


;- MAIN TEST
If OpenWindow(#Window_0, 260, 225, 700, 571, "PBMap", #PB_Window_SystemMenu | #PB_Window_MinimizeGadget | #PB_Window_TitleBar | #PB_Window_ScreenCentered | #PB_Window_SizeGadget)
  
  LoadFont(0, "Arial", 12)
  LoadFont(1, "Arial", 12, #PB_Font_Bold)
  LoadFont(2, "Arial", 8)
  
  TextGadget(#Text_1, 530, 10, 60, 15, "Movements")
  ; ButtonGadget(#Gdt_RotateLeft, 550, 070, 30, 30, "LRot")  : SetGadgetFont(#Gdt_RotateLeft, FontID(2)) 
  ; ButtonGadget(#Gdt_RotateRight, 610, 070, 30, 30, "RRot")  : SetGadgetFont(#Gdt_RotateRight, FontID(2)) 
  ButtonGadget(#Gdt_Left,  550, 60, 30, 30, Chr($25C4))  : SetGadgetFont(#Gdt_Left, FontID(0)) 
  ButtonGadget(#Gdt_Right, 610, 60, 30, 30, Chr($25BA))  : SetGadgetFont(#Gdt_Right, FontID(0)) 
  ButtonGadget(#Gdt_Up,    580, 030, 30, 30, Chr($25B2))  : SetGadgetFont(#Gdt_Up, FontID(0)) 
  ButtonGadget(#Gdt_Down,  580, 90, 30, 30, Chr($25BC))  : SetGadgetFont(#Gdt_Down, FontID(0)) 
  TextGadget(#Text_2, 530, 120, 60, 15, "Zoom")
  ButtonGadget(#Button_4, 550, 140, 50, 30, " + ")        : SetGadgetFont(#Button_4, FontID(1)) 
  ButtonGadget(#Button_5, 600, 140, 50, 30, " - ")        : SetGadgetFont(#Button_5, FontID(1)) 
  TextGadget(#Text_3, 530, 190, 50, 15, "Latitude ")
  StringGadget(#StringLatitude, 580, 190, 90, 20, "")
  TextGadget(#Text_4, 530, 210, 50, 15, "Longitude ")
  StringGadget(#StringLongitude, 580, 210, 90, 20, "")
  ButtonGadget(#Gdt_AddMarker, 530, 240, 150, 30, "Add Marker")
  ButtonGadget(#Gdt_LoadGpx, 530, 270, 150, 30, "Load GPX")    
  ButtonGadget(#Gdt_SaveGpx, 530, 300, 150, 30, "Save GPX")    
  ButtonGadget(#Gdt_AddOpenseaMap, 530, 330, 150, 30, "Show/Hide OpenSeaMap", #PB_Button_Toggle)
  ButtonGadget(#Gdt_AddHereMap, 530, 360, 150, 30, "Show/Hide HERE Aerial", #PB_Button_Toggle)
  ButtonGadget(#Gdt_AddGeoServerMap, 530, 390, 150, 30, "Show/Hide Geoserver layer", #PB_Button_Toggle)
  ButtonGadget(#Gdt_Degrees, 530, 420, 150, 30, "Show/Hide Degrees", #PB_Button_Toggle)
  ButtonGadget(#Gdt_EditMode, 530, 450, 150, 30, "Edit mode ON/OFF", #PB_Button_Toggle)
  ButtonGadget(#Gdt_ClearDiskCache, 530, 480, 150, 30, "Clear disk cache", #PB_Button_Toggle)
  TextGadget(#TextGeoLocationQuery, 530, 515, 150, 15, "Enter an address")
  StringGadget(#StringGeoLocationQuery, 530, 530, 150, 20, "")
  SetActiveGadget(#StringGeoLocationQuery)
  AddKeyboardShortcut(#Window_0, #PB_Shortcut_Return, #MenuEventGeoLocationStringEnter)
  ; *** TODO : code to remove when the SetActiveGadget(-1) will be fixed
  CompilerIf #PB_Compiler_OS = #PB_OS_Linux
    Define Dummy = ButtonGadget(#PB_Any, 0, 0, 1, 1, "Dummy") 
    HideGadget(Dummy, 1) 
  CompilerElse
    Define Dummy = -1
  CompilerEndIf
  ; ***
  Define Event.i, Gadget.i, Quit.b = #False
  Define pfValue.d
  Define Degrees = 1
  Define *Track
  Define *PBMap
  
  ; Our main gadget
  ;*PBMap = PBMap::InitPBMap(#Window_0)
  PBMap::MapGadget(#Map, 10, 10, 512, 512)    
  PBMap::SetOption(#Map, "ShowDegrees", "1") : Degrees = 0
  PBMap::SetOption(#Map, "ShowDebugInfos", "1")
  PBMap::SetDebugLevel(5)
  PBMap::SetOption(#Map, "Verbose", "0")
  PBMap::SetOption(#Map, "ShowScale", "1")    
  PBMap::SetOption(#Map, "Warning", "1")
  PBMap::SetOption(#Map, "ShowMarkersLegend", "1")
  PBMap::SetOption(#Map, "ShowTrackKms", "1")
  PBMap::SetOption(#Map, "ColourFocus", "$FFFF00AA") 
  
  PBMap::SetCallBackMainPointer(#Map, @MainPointer())                   ; To change the main pointer (center of the view)
  PBMap::SetCallBackLocation(#Map, @UpdateLocation())                   ; To obtain realtime coordinates
  PBMap::SetLocation(#Map, -36.81148, 175.08634,12)                     ; Change the PBMap coordinates
  PBMap::SetMapScaleUnit(#Map, PBMAP::#SCALE_KM)                        ; To change the scale unit
  PBMap::AddMarker(#Map, 49.0446828398, 2.0349812508, "", "", -1, @MyMarker())  ; To add a marker with a customised GFX
  PBMap::SetCallBackMarker(#Map, @MarkerMoveCallBack())
  ;PBMap::SetCallBackDrawTile(@DrawTileCallBack())
  ;PBMap::SetCallBackModifyTileFile(@ModifyTileFileCallback())
  
  Repeat
    Event = WaitWindowEvent()
    Select Event
      Case #PB_Event_CloseWindow : Quit = 1
      Case #PB_Event_Gadget ; {
        Gadget = EventGadget()
        Select Gadget
          Case #Gdt_Up
            PBMap::SetLocation(#Map, 10* 360 / Pow(2, PBMap::GetZoom(#Map) + 8), 0, 0, #PB_Relative)
          Case #Gdt_Down
            PBMap::SetLocation(#Map, 10* -360 / Pow(2, PBMap::GetZoom(#Map) + 8), 0, 0, #PB_Relative)
          Case #Gdt_Left
            PBMap::SetLocation(#Map, 0, 10* -360 / Pow(2, PBMap::GetZoom(#Map) + 8), 0, #PB_Relative)
          Case #Gdt_Right
            PBMap::SetLocation(#Map, 0, 10* 360 / Pow(2, PBMap::GetZoom(#Map) + 8), 0, #PB_Relative)
            ; Case #Gdt_RotateLeft
            ; PBMAP::SetAngle(-5,#PB_Relative) 
            ; PBMap::Refresh()
            ; Case #Gdt_RotateRight
            ; PBMAP::SetAngle(5,#PB_Relative) 
            ; PBMap::Refresh()
          Case #Button_4
            PBMap::SetZoom(#Map, 1)
          Case #Button_5
            PBMap::SetZoom(#Map,  -1)
          Case #Gdt_LoadGpx
            *Track = PBMap::LoadGpxFile(#Map, OpenFileRequester("Choose a file to load", "", "Gpx|*.gpx", 0))
            PBMap::SetTrackColour(#Map, *Track, RGBA(Random(255), Random(255), Random(255), 128))
          Case #Gdt_SaveGpx
            If *Track
              If PBMap::SaveGpxFile(#Map, SaveFileRequester("Choose a filename", "mytrack.gpx", "Gpx|*.gpx", 0), *Track)
                MessageRequester("PBMap", "Saving OK !", #PB_MessageRequester_Ok) 
              Else
                MessageRequester("PBMap", "Problem while saving.", #PB_MessageRequester_Ok)                 
              EndIf  
            Else
              MessageRequester("PBMap", "No track to save.", #PB_MessageRequester_Ok) 
            EndIf
          Case #StringLatitude, #StringLongitude
            Select EventType()
              Case #PB_EventType_Focus
                AddKeyboardShortcut(#Window_0, #PB_Shortcut_Return, #MenuEventLonLatStringEnter)
              Case #PB_EventType_LostFocus
                RemoveKeyboardShortcut(#Window_0, #PB_Shortcut_Return)
            EndSelect
          Case #Gdt_AddMarker
            PBMap::AddMarker(#Map, ValD(GetGadgetText(#StringLatitude)), ValD(GetGadgetText(#StringLongitude)), "", "Test", RGBA(Random(255), Random(255), Random(255), 255))
          Case #Gdt_AddOpenseaMap
            If PBMap::IsLayer(#Map, "OpenSeaMap")
              PBMap::DeleteLayer(#Map, "OpenSeaMap")
              SetGadgetState(#Gdt_AddOpenseaMap, 0)
            Else
              PBMap::AddOSMServerLayer(#Map, "OpenSeaMap", 3, "http://t1.openseamap.org/seamark/") ; Add a special osm overlay map on layer nb 3
              SetGadgetState(#Gdt_AddOpenseaMap, 1)
            EndIf
            PBMap::Refresh(#Map)
          Case #Gdt_AddHereMap
            If PBMap::IsLayer(#Map, "Here")
              PBMap::DeleteLayer(#Map, "Here")
              SetGadgetState(#Gdt_AddHereMap, 0)
            Else
              If PBMap::GetOption(#Map, "appid") <> "" And PBMap::GetOption(#Map, "appcode") <> ""
                PBMap::AddHereServerLayer(#Map, "Here", 2) ; Add a "HERE" overlay map on layer nb 2
                PBMap::SetLayerAlpha(#Map, "Here", 0.75)
              Else
                MessageRequester("Info", "Don't forget to register on HERE and change the following line or edit options file")
                PBMap::AddHereServerLayer(#Map, "Here", 2, "my_id", "my_code") ; Add a here overlay map on layer nb 2
              EndIf
              SetGadgetState(#Gdt_AddHereMap, 1)
            EndIf
            PBMap::Refresh(#Map)
          Case #Gdt_AddGeoServerMap
            If PBMap::IsLayer(#Map, "GeoServer")
              PBMap::DeleteLayer(#Map, "GeoServer")
              SetGadgetState(#Gdt_AddGeoServerMap, 0)
            Else
              PBMap::AddGeoServerLayer(#Map, "GeoServer", 3, "demolayer", "http://localhost:8080/", "geowebcache/service/gmaps", "image/png") ; Add a geoserver overlay map on layer nb 3
              PBMap::SetLayerAlpha(#Map, "GeoServer", 0.75)
              SetGadgetState(#Gdt_AddGeoServerMap, 1)
            EndIf
            PBMap::Refresh(#Map)
          Case #Gdt_Degrees
            Degrees = 1 - Degrees
            PBMap::SetOption(#Map, "ShowDegrees", Str(Degrees))
            PBMap::Refresh(#Map)
            SetGadgetState(#Gdt_Degrees, Degrees)
          Case #Gdt_EditMode
            If PBMap::GetMode(#Map) <> PBMap::#MODE_EDIT
              PBMap::SetMode(#Map, PBMap::#MODE_EDIT)
              SetGadgetState(#Gdt_EditMode, 1)
            Else
              PBMap::SetMode(#Map, PBMap::#MODE_DEFAULT)
              SetGadgetState(#Gdt_EditMode, 0)
            EndIf
          Case #Gdt_ClearDiskCache
            PBMap::ClearDiskCache(#Map)
          Case #StringGeoLocationQuery
            Select EventType()
              Case #PB_EventType_Focus
                AddKeyboardShortcut(#Window_0, #PB_Shortcut_Return, #MenuEventGeoLocationStringEnter)
              Case #PB_EventType_LostFocus
                RemoveKeyboardShortcut(#Window_0, #PB_Shortcut_Return)
            EndSelect
        EndSelect
      Case #PB_Event_SizeWindow
        ResizeAll()
      Case #PB_Event_Menu
        ; Receive "enter" key events
        Select EventMenu()
          Case #MenuEventGeoLocationStringEnter
            If GetGadgetText(#StringGeoLocationQuery) <> ""
              PBMap::NominatimGeoLocationQuery(#Map, GetGadgetText(#StringGeoLocationQuery))
              PBMap::Refresh(#Map)
            EndIf
            ; *** TODO : code to change when the SetActiveGadget(-1) will be fixed
            SetActiveGadget(Dummy)
            ; ***
          Case  #MenuEventLonLatStringEnter
            PBMap::SetLocation(#Map, ValD(GetGadgetText(#StringLatitude)), ValD(GetGadgetText(#StringLongitude)))                     ; Change the PBMap coordinates
            PBMap::Refresh(#Map)
        EndSelect
    EndSelect
  Until Quit = #True
  
  PBMap::FreeMapGadget(#Map)
EndIf


; IDE Options = PureBasic 5.73 LTS (Windows - x64)
; CursorPosition = 7
; Folding = --
; EnableThread
; EnableXP