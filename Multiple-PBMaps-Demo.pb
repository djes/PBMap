; Based on the orginal PBMap example (delivered with the package in Feb. 2018), this is an example with
; less functionality, but with 2 different Canvas Map gadgets placed in 2 tabs of a PanelGadget...
; (for testing purposes related to my GeoWorldEditor)
;
; Author: André Beer
; Last change: 26. Feb. 2018
; Modified by djes : 01. March 2018
; Adapted to new PBMap syntax by André: 02. March 2018
;
; ****************************************************************
;
;- Example of application
;
; ****************************************************************
XIncludeFile "PBMap.pb"

InitNetwork()

Enumeration
  #Window_0
  #Map
  #Gdt_Left
  #Gdt_Right
  #Gdt_Up
  #Gdt_Down
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
  #Gdt_AddMarker
  #Gdt_Degrees
  #Gdt_ClearDiskCache
  #TextGeoLocationQuery
  #StringGeoLocationQuery
  ; Additions for a 2nd panel:
  #PanelGadget
  #Map2_Canvas
  #Map2_Move
  #Map2_Left
  #Map2_Right
  #Map2_Up
  #Map2_Down
  #Map2_Zoom
  #Map2_ZoomIn
  #Map2_ZoomOut
  #Map2_LatitudeText
  #Map2_StringLatitude
  #Map2_LongitudeText
  #Map2_StringLongitude 
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
  Protected PanelTabHeight = GetGadgetAttribute(#PanelGadget, #PB_Panel_TabHeight)
  ResizeGadget(#PanelGadget, #PB_Ignore, #PB_Ignore, WindowWidth(#Window_0), WindowHeight(#Window_0)-PanelTabHeight)
  Protected PanelItemWidth = GetGadgetAttribute(#PanelGadget, #PB_Panel_ItemWidth)
  Protected PanelItemHeight = GetGadgetAttribute(#PanelGadget, #PB_Panel_ItemHeight)
  ; First tab:
  ResizeGadget(#Map, 10, 10, PanelItemWidth-198, PanelItemHeight-59)
  ResizeGadget(#Text_1, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_Left, PanelItemWidth-150, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_Right, PanelItemWidth-90, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_Up,   PanelItemWidth-120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_Down, PanelItemWidth-120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Text_2, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Button_4, PanelItemWidth-150, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Button_5, PanelItemWidth-100, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Text_3, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#StringLatitude, PanelItemWidth-120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#StringLongitude, PanelItemWidth-120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Text_4, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_AddMarker, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_Degrees, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Gdt_ClearDiskCache, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#TextGeoLocationQuery, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#StringGeoLocationQuery, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ; Second tab:
  ResizeGadget(#Map2_Canvas, 10, 10, PanelItemWidth-198, PanelItemHeight-59)
  ResizeGadget(#Map2_Move, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Map2_Left, PanelItemWidth-150, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Map2_Right, PanelItemWidth-90, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Map2_Up,   PanelItemWidth-120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Map2_Down, PanelItemWidth-120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Map2_Zoom, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Map2_ZoomIn, PanelItemWidth-150, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Map2_ZoomOut, PanelItemWidth-100, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Map2_LatitudeText, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Map2_StringLatitude, PanelItemWidth-120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
  ResizeGadget(#Map2_LongitudeText, PanelItemWidth-170, #PB_Ignore, #PB_Ignore, #PB_Ignore) 
  ResizeGadget(#Map2_StringLongitude, PanelItemWidth-120, #PB_Ignore, #PB_Ignore, #PB_Ignore)
 
  ; Refresh the PBMap:
  PBMap::Refresh(#Map)
  PBMap::Refresh(#Map2_Canvas)
EndProcedure

;- MAIN TEST
If OpenWindow(#Window_0, 260, 225, 720, 595, "PBMap", #PB_Window_SystemMenu | #PB_Window_MinimizeGadget | #PB_Window_TitleBar | #PB_Window_ScreenCentered | #PB_Window_SizeGadget)
  ; ***
  Define Event.i, Gadget.i, Quit.b = #False
  Define pfValue.d
  Define Degrees = 1
  Define *Track
  Define a, ActivePanel
 
  LoadFont(0, "Arial", 12)
  LoadFont(1, "Arial", 12, #PB_Font_Bold)
  LoadFont(2, "Arial", 8)
 
  PanelGadget(#PanelGadget, 0, 0, 720, 595)
  AddGadgetItem(#PanelGadget, 0, "Map 1")
    TextGadget(#Text_1, 530, 10, 60, 15, "Movements")
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
    ButtonGadget(#Gdt_Degrees, 530, 420, 150, 30, "Show/Hide Degrees", #PB_Button_Toggle)
    ButtonGadget(#Gdt_ClearDiskCache, 530, 480, 150, 30, "Clear disk cache", #PB_Button_Toggle)
    TextGadget(#TextGeoLocationQuery, 530, 515, 150, 15, "Enter an address")
    StringGadget(#StringGeoLocationQuery, 530, 530, 150, 20, "")
    SetActiveGadget(#StringGeoLocationQuery)
    
    ; Our main gadget
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
    PBMAP::SetMapScaleUnit(#Map, PBMAP::#SCALE_KM)                        ; To change the scale unit
    PBMap::AddMarker(#Map, 49.0446828398, 2.0349812508, "", "", -1, @MyMarker())  ; To add a marker with a customised GFX
    PBMap::SetCallBackMarker(#Map, @MarkerMoveCallBack())
    PBMap::SetCallBackDrawTile(#Map, @DrawTileCallBack())
    PBMap::SetCallBackModifyTileFile(#Map, @ModifyTileFileCallback())
    
  AddGadgetItem(#PanelGadget, 1, "Map 2")
    TextGadget(#Map2_Move, 530, 10, 60, 15, "Movements")
    ButtonGadget(#Map2_Left,  550, 60, 30, 30, Chr($25C4))  : SetGadgetFont(#Gdt_Left, FontID(0))
    ButtonGadget(#Map2_Right, 610, 60, 30, 30, Chr($25BA))  : SetGadgetFont(#Gdt_Right, FontID(0))
    ButtonGadget(#Map2_Up,    580, 030, 30, 30, Chr($25B2))  : SetGadgetFont(#Gdt_Up, FontID(0))
    ButtonGadget(#Map2_Down,  580, 90, 30, 30, Chr($25BC))  : SetGadgetFont(#Gdt_Down, FontID(0))
    TextGadget(#Map2_Zoom, 530, 120, 60, 15, "Zoom")
    ButtonGadget(#Map2_ZoomIn, 550, 140, 50, 30, " + ")        : SetGadgetFont(#Button_4, FontID(1))
    ButtonGadget(#Map2_ZoomOut, 600, 140, 50, 30, " - ")        : SetGadgetFont(#Button_5, FontID(1))
    TextGadget(#Map2_LatitudeText, 530, 190, 50, 15, "Latitude ")
    StringGadget(#Map2_StringLatitude, 580, 190, 90, 20, "")
    TextGadget(#Map2_LongitudeText, 530, 210, 50, 15, "Longitude ")
    StringGadget(#Map2_StringLongitude, 580, 210, 90, 20, "")
   
    ; Our second map:
    PBMap::MapGadget(#Map2_Canvas, 10, 10, 512, 512)
    PBMap::SetOption(#Map2_Canvas, "ShowDegrees", "1") : Degrees = 0
    PBMap::SetOption(#Map2_Canvas, "ShowDebugInfos", "1")
    PBMap::SetDebugLevel(5)
    PBMap::SetOption(#Map2_Canvas, "Verbose", "0")
    PBMap::SetOption(#Map2_Canvas, "ShowScale", "1")   
    PBMap::SetOption(#Map2_Canvas, "Warning", "1")
    PBMap::SetOption(#Map2_Canvas, "ShowMarkersLegend", "1")
    PBMap::SetOption(#Map2_Canvas, "ShowTrackKms", "1")
    PBMap::SetOption(#Map2_Canvas, "ColourFocus", "$FFFF00AA")
    PBMap::SetCallBackMainPointer(#Map2_Canvas, @MainPointer())                   ; To change the main pointer (center of the view)
    PBMap::SetCallBackLocation(#Map2_Canvas, @UpdateLocation())                   ; To obtain realtime coordinates
    PBMap::SetLocation(#Map2_Canvas, 6.81148, 15.08634,12)                     ; Change the PBMap coordinates
    PBMAP::SetMapScaleUnit(#Map2_Canvas, PBMAP::#SCALE_KM)                        ; To change the scale unit
    PBMap::AddMarker(#Map2_Canvas, 49.0446828398, 2.0349812508)
   
  CloseGadgetList()
 
  ActivePanel = 2   ; Set the current active panel (1 = Map1, 2 = Map2)
  SetGadgetState(#PanelGadget, 1)
   
  AddKeyboardShortcut(#Window_0, #PB_Shortcut_Return, #MenuEventGeoLocationStringEnter)
  ; *** TODO : code to remove when the SetActiveGadget(-1) will be fixed
  CompilerIf #PB_Compiler_OS = #PB_OS_Linux
    Define Dummy = ButtonGadget(#PB_Any, 0, 0, 1, 1, "Dummy")
    HideGadget(Dummy, 1)
  CompilerElse
    Define Dummy = -1
  CompilerEndIf
 
  Repeat
    Event = WaitWindowEvent()
    Select Event
      Case #PB_Event_CloseWindow : Quit = 1
      Case #PB_Event_Gadget ; {
        Gadget = EventGadget()
        Select Gadget
          Case #PanelGadget
            Select EventType()
              Case #PB_EventType_Change
                a = GetGadgetState(#PanelGadget)
                If a <> ActivePanel
                  ActivePanel = a
                  If ActivePanel = 0
                    ; ....
                  Else
                    ; ....
                  EndIf
                EndIf
            EndSelect
          Case #Gdt_Up
            PBMap::SetLocation(#Map, 10* 360 / Pow(2, PBMap::GetZoom(#Map) + 8), 0, 0, #PB_Relative)
          Case #Map2_Up
            PBMap::SetLocation(#Map2_Canvas, 10* 360 / Pow(2, PBMap::GetZoom(#Map2_Canvas) + 8), 0, 0, #PB_Relative)
          Case #Gdt_Down
            PBMap::SetLocation(#Map, 10* -360 / Pow(2, PBMap::GetZoom(#Map) + 8), 0, 0, #PB_Relative)
          Case #Map2_Down
            PBMap::SetLocation(#Map2_Canvas, 10* -360 / Pow(2, PBMap::GetZoom(#Map2_Canvas) + 8), 0, 0, #PB_Relative)
          Case #Gdt_Left
            PBMap::SetLocation(#Map, 0, 10* -360 / Pow(2, PBMap::GetZoom(#Map) + 8), 0, #PB_Relative)
          Case #Map2_Left
            PBMap::SetLocation(#Map2_Canvas, 0, 10* -360 / Pow(2, PBMap::GetZoom(#Map2_Canvas) + 8), 0, #PB_Relative)
          Case #Gdt_Right
            PBMap::SetLocation(#Map, 0, 10* 360 / Pow(2, PBMap::GetZoom(#Map) + 8), 0, #PB_Relative)
          Case #Map2_Right
            PBMap::SetLocation(#Map2_Canvas, 0, 10* 360 / Pow(2, PBMap::GetZoom(#Map2_Canvas) + 8), 0, #PB_Relative)
          Case #Button_4
            PBMap::SetZoom(#Map, 1)
          Case #Map2_ZoomIn
            PBMap::SetZoom(#Map2_Canvas, 1)
          Case #Button_5
            PBMap::SetZoom(#Map, - 1)
          Case #Map2_ZoomOut
            PBMap::SetZoom(#Map2_Canvas, - 1)
          Case #StringLatitude, #StringLongitude, #Map2_StringLatitude, #Map2_StringLongitude
            Select EventType()
              Case #PB_EventType_Focus
                AddKeyboardShortcut(#Window_0, #PB_Shortcut_Return, #MenuEventLonLatStringEnter)
              Case #PB_EventType_LostFocus
                RemoveKeyboardShortcut(#Window_0, #PB_Shortcut_Return)
            EndSelect
          Case #Gdt_AddMarker
            PBMap::AddMarker(#Map, ValD(GetGadgetText(#StringLatitude)), ValD(GetGadgetText(#StringLongitude)), "", "Test", RGBA(Random(255), Random(255), Random(255), 255))
          Case #Gdt_Degrees
            Degrees = 1 - Degrees
            PBMap::SetOption(#Map, "ShowDegrees", Str(Degrees))
            PBMap::Refresh(#Map)
            SetGadgetState(#Gdt_Degrees, Degrees)
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
  PBMap::FreeMapGadget(#Map2_Canvas)
EndIf
; IDE Options = PureBasic 5.61 (Windows - x64)
; CursorPosition = 204
; FirstLine = 176
; Folding = --
; EnableThread
; EnableXP
; CompileSourceDirectory