;******************************************************************** 
; Program:           PBMap
; Description:       Permits the use of tiled maps like 
;                    OpenStreetMap in a handy PureBASIC module
; Author:            Thyphoon, djes And Idle
; Date:              Mai 17, 2016
; License:           PBMap : Free, unrestricted, credit 
;                            appreciated but not required.
;                    OSM : see http://www.openstreetmap.org/copyright
; Note:              Please share improvement !
; Thanks:            Progi1984, yves86
;******************************************************************** 

CompilerIf #PB_Compiler_Thread = #False
  MessageRequester("Warning !!","You must enable ThreadSafe support in compiler options",#PB_MessageRequester_Ok )
  End
CompilerEndIf 

EnableExplicit

InitNetwork()
UsePNGImageDecoder()
UsePNGImageEncoder()

DeclareModule PBMap
  #Red = 255
  
  ;-Show debug infos  
  Global Verbose = 0
  Global MyDebugLevel = 0
  
  #SCALE_NAUTICAL = 1 
  #SCALE_KM = 0 
  
  #MODE_DEFAULT = 0
  #MODE_HAND = 1
  #MODE_SELECT = 2
  #MODE_EDIT = 3
  
  #MARKER_EDIT_EVENT = #PB_Event_FirstCustomValue
  
  Structure GeographicCoordinates
    Longitude.d
    Latitude.d
  EndStructure
  
  ;-Declarations
  Declare InitPBMap(window)
  Declare SetOption(Option.s, Value.s)
  Declare LoadOptions(PreferencesFile.s = "PBMap.prefs")
  Declare SaveOptions(PreferencesFile.s = "PBMap.prefs")
  Declare.i AddMapServerLayer(LayerName.s, Order.i, ServerURL.s = "http://tile.openstreetmap.org/", TileSize = 256, ZoomMin = 0, ZoomMax = 18)
  Declare DeleteLayer(Nb.i)
  Declare BindMapGadget(Gadget.i)
  Declare MapGadget(Gadget.i, X.i, Y.i, Width.i, Height.i)
  Declare SetLocation(latitude.d, longitude.d, Zoom = -1, mode.i = #PB_Absolute)
  Declare Drawing()
  Declare SetAngle(Angle.d, Mode = #PB_Absolute) 
  Declare SetZoom(Zoom.i, mode.i = #PB_Relative)
  Declare ZoomToArea(MinY.d, MaxY.d, MinX.d, MaxX.d)
  Declare ZoomToTracks(*Tracks)
  Declare SetCallBackLocation(*CallBackLocation)
  Declare SetCallBackMainPointer(CallBackMainPointer.i)
  Declare SetMapScaleUnit(ScaleUnit=PBMAP::#SCALE_KM) 
  Declare.i LoadGpxFile(file.s);  
  Declare ClearTracks()
  Declare DeleteTrack(*Ptr)
  Declare DeleteSelectedTracks()
  Declare SetTrackColour(*Ptr, Colour.i)
  Declare.i AddMarker(Latitude.d, Longitude.d, Identifier.s = "", Legend.s = "", color.l=-1, CallBackPointer.i = -1)
  Declare ClearMarkers()
  Declare DeleteMarker(*Ptr)
  Declare DeleteSelectedMarkers()
  Declare Quit()
  Declare Error(msg.s)
  Declare Refresh()
  Declare.d GetLatitude()
  Declare.d GetLongitude()
  Declare.d MouseLatitude()
  Declare.d MouseLongitude()
  Declare.d GetAngle()
  Declare.i GetZoom()
  Declare.i GetMode()
  Declare SetMode(Mode.i = #MODE_DEFAULT)
  Declare NominatimGeoLocationQuery(Address.s, *ReturnPosition.GeographicCoordinates = 0) ;Send back the position *ptr.GeographicCoordinates
EndDeclareModule

Module PBMap 
  
  EnableExplicit
    
  Structure PixelCoordinates
    x.d
    y.d
  EndStructure
  
  Structure Coordinates
    x.d
    y.d
  EndStructure
  
  ;- Tile Structure
  Structure Tile
    nImage.i
    key.s
    URL.s
    CacheFile.s
    GetImageThread.i
    RetryNb.i
  EndStructure
  
  Structure BoundingBox 
    NorthWest.GeographicCoordinates
    SouthEast.GeographicCoordinates 
    BottomLeft.PixelCoordinates
    TopRight.PixelCoordinates   
  EndStructure
  
  Structure DrawingParameters
    Canvas.i
    CenterX.d                                     ; Gadget center in screen relative pixels
    CenterY.d
    GeographicCoordinates.GeographicCoordinates   ; Real center
    TileCoordinates.Coordinates                   ; Center coordinates in tile.decimal
    Bounds.BoundingBox                            ; Drawing boundaries in lat/lon
    Height.d                                      ; Drawing height in degrees
    Width.d                                       ; Drawing width in degrees
    PBMapZoom.i
    DeltaX.i                                      ; Screen relative pixels tile shift
    DeltaY.i
    Dirty.i
    End.i
  EndStructure  
  
  Structure ImgMemCach
    nImage.i
    *Tile.Tile
    TimeStackPosition.i
    Alpha.i
  EndStructure
  
  Structure ImgMemCachKey
    MapKey.s
  EndStructure
  
  Structure TileMemCach
    Map Images.ImgMemCach(4096)
    List ImagesTimeStack.ImgMemCachKey()           ; Usage of the tile (first = older)
  EndStructure
  
  Structure Marker
    GeographicCoordinates.GeographicCoordinates    ; Marker latitude and longitude
    Identifier.s
    Legend.s
    Color.l                                        ; Marker color
    Focus.i
    Selected.i                                     ; Is the marker selected ?
    CallBackPointer.i                              ; @Procedure(X.i, Y.i) to DrawPointer (you must use VectorDrawing lib)
    EditWindow.i
  EndStructure
  
  ;-Options
  Structure Option
    HDDCachePath.s                                 ; Path where to load and save tiles downloaded from server
    DefaultOSMServer.s                             ; Base layer OSM server
    WheelMouseRelative.i
    ScaleUnit.i                                    ; Scale unit to use for measurements
    Proxy.i                                        ; Proxy ON/OFF
    ProxyURL.s
    ProxyPort.s
    ProxyUser.s
    ProxyPassword.s
    ShowDegrees.i
    ShowDebugInfos.i
    ShowScale.i
    ShowTrack.i
    ShowTrackKms.i
    ShowMarkers.i
    ShowPointer.i
    TimerInterval.i
    MaxMemCache.i                                  ; in MiB
    ShowMarkersNb.i
    ShowMarkersLegend.i
    ;Drawing stuff
    StrokeWidthTrackDefault.i
    ;Colours
    ColourFocus.i
    ColourSelected.i
    ColourTrackDefault.i
  EndStructure
  
  Structure Layer
    Order.i                                        ; Layer nb
    Name.s
    ServerURL.s                                    ; Web URL ex: http://tile.openstreetmap.org/  
  EndStructure
  
  Structure Box
    x1.i
    y1.i
    x2.i
    y2.i
  EndStructure 
  
  Structure Tracks
    List Track.GeographicCoordinates()             ; To display a GPX track
    BoundingBox.Box
    Visible.i
    Focus.i
    Selected.i
    Colour.i
    StrokeWidth.i
  EndStructure
  
  ;-PBMap Structure
  Structure PBMap
    Window.i                                       ; Parent Window
    Gadget.i                                       ; Canvas Gadget Id 
    Font.i                                         ; Font to uses when write on the map 
    Timer.i                                        ; Redraw/update timer
    
    GeographicCoordinates.GeographicCoordinates    ; Latitude and Longitude from focus point
    Drawing.DrawingParameters                      ; Drawing parameters based on focus point
    
    CallBackLocation.i                             ; @Procedure(latitude.d,lontitude.d)
    CallBackMainPointer.i                          ; @Procedure(X.i, Y.i) to DrawPointer (you must use VectorDrawing lib)
    
    PixelCoordinates.PixelCoordinates              ; Actual focus point coords in pixels (global)
    MoveStartingPoint.PixelCoordinates             ; Start mouse position coords when dragging the map
    
    List Layers.Layer()                            ; 
    
    Angle.d
    ZoomMin.i                                      ; Min Zoom supported by server
    ZoomMax.i                                      ; Max Zoom supported by server
    Zoom.i                                         ; Current zoom
    TileSize.i                                     ; Tile size downloaded on the server ex : 256
    
    MemCache.TileMemCach                           ; Images in memory cache
    
    Mode.i                                         ; User mode : 0 (default)->hand (moving map) and select markers, 1->hand, 2->select only (moving objects), 3->drawing (todo) 
    Redraw.i
    Moving.i
    Dirty.i                                        ; To signal that drawing need a refresh
    
    List TracksList.Tracks()
    List Markers.Marker()                          ; To diplay marker
    EditMarker.l
    
    ImgLoading.i                                   ; Image Loading Tile
    ImgNothing.i                                   ; Image Nothing Tile
    
    Options.option                                 ; Options
    
  EndStructure
  
  #PB_MAP_REDRAW = #PB_EventType_FirstCustomValue + 1 
  #PB_MAP_RETRY  = #PB_EventType_FirstCustomValue + 2
  #PB_MAP_TILE_CLEANUP = #PB_EventType_FirstCustomValue + 3
  
  ;-Global variables
  Global PBMap.PBMap, Null.i
  
  ;Shows an error msg and terminates the program
  Procedure Error(msg.s)
    MessageRequester("PBMap", msg, #PB_MessageRequester_Ok)
    End
  EndProcedure
  
  ;Send debug infos to stdout (allowing mixed debug infos with curl or other libs)
  Procedure MyDebug(msg.s, DbgLevel = 0)
    If Verbose And DbgLevel >= MyDebugLevel 
      PrintN(msg)
      ;Debug msg  
    EndIf
  EndProcedure
  
  ;- *** GetText - Translation purpose
  IncludeFile "gettext.pbi"
  
  ;- *** CURL specific
  ; (program has To be compiled in console format for curl debug infos)
  
  IncludeFile "libcurl.pbi" ; https://github.com/deseven/pbsamples/tree/master/crossplatform/libcurl
  
  Global *ReceiveHTTPToMemoryBuffer, ReceiveHTTPToMemoryBufferPtr.i, ReceivedData.s
   
  ProcedureC ReceiveHTTPWriteToMemoryFunction(*ptr, Size.i, NMemB.i, *Stream)
    Protected SizeProper.i  = Size & 255
    Protected NMemBProper.i = NMemB
    If *ReceiveHTTPToMemoryBuffer = 0
      *ReceiveHTTPToMemoryBuffer = AllocateMemory(SizeProper * NMemBProper)
      If *ReceiveHTTPToMemoryBuffer = 0
        Error("Curl : Problem allocating memory")
      EndIf
    Else
      *ReceiveHTTPToMemoryBuffer = ReAllocateMemory(*ReceiveHTTPToMemoryBuffer, MemorySize(*ReceiveHTTPToMemoryBuffer) + SizeProper * NMemBProper)
      If *ReceiveHTTPToMemoryBuffer = 0
        Error("Curl : Problem reallocating memory")
      EndIf  
    EndIf
    CopyMemory(*ptr, *ReceiveHTTPToMemoryBuffer + ReceiveHTTPToMemoryBufferPtr, SizeProper * NMemBProper)
    ReceiveHTTPToMemoryBufferPtr + SizeProper * NMemBProper
    ProcedureReturn SizeProper * NMemBProper
  EndProcedure
  
  Procedure.i CurlReceiveHTTPToMemory(URL$, ProxyURL$="", ProxyPort$="", ProxyUser$="", ProxyPassword$="")
    Protected *Buffer, curl.i, Timeout.i, res.i, respcode.l
    If Len(URL$)
      curl  = curl_easy_init()
      If curl
        Timeout = 3
        curl_easy_setopt(curl, #CURLOPT_URL, str2curl(URL$))
        curl_easy_setopt(curl, #CURLOPT_SSL_VERIFYPEER, 0)
        curl_easy_setopt(curl, #CURLOPT_SSL_VERIFYHOST, 0)
        curl_easy_setopt(curl, #CURLOPT_HEADER, 0)   
        curl_easy_setopt(curl, #CURLOPT_FOLLOWLOCATION, 1)
        curl_easy_setopt(curl, #CURLOPT_TIMEOUT, Timeout)
        If Verbose
          curl_easy_setopt(curl, #CURLOPT_VERBOSE, 1)
        EndIf
        curl_easy_setopt(curl, #CURLOPT_FAILONERROR, 1)
        If Len(ProxyURL$)
          ;curl_easy_setopt(curl, #CURLOPT_HTTPPROXYTUNNEL, #True)
          If Len(ProxyPort$)
            ProxyURL$ + ":" + ProxyPort$
          EndIf
          ; Debug ProxyURL$
          curl_easy_setopt(curl, #CURLOPT_PROXY, str2curl(ProxyURL$))
          If Len(ProxyUser$)
            If Len(ProxyPassword$)
              ProxyUser$ + ":" + ProxyPassword$
            EndIf
            ;Debug ProxyUser$
            curl_easy_setopt(curl, #CURLOPT_PROXYUSERPWD, str2curl(ProxyUser$))
          EndIf
        EndIf
        curl_easy_setopt(curl, #CURLOPT_WRITEFUNCTION, @ReceiveHTTPWriteToMemoryFunction())
        res = curl_easy_perform(curl)
        If res = #CURLE_OK
          *Buffer = AllocateMemory(ReceiveHTTPToMemoryBufferPtr)
          If *Buffer
            CopyMemory(*ReceiveHTTPToMemoryBuffer, *Buffer, ReceiveHTTPToMemoryBufferPtr)
            FreeMemory(*ReceiveHTTPToMemoryBuffer)
            *ReceiveHTTPToMemoryBuffer = #Null
            ReceiveHTTPToMemoryBufferPtr = 0
          Else
            MyDebug("Problem allocating buffer", 4)         
          EndIf        
          ;curl_easy_cleanup(curl) ;Was its original place but moved below as it seems more logical to me.
        Else
          curl_easy_getinfo(curl, #CURLINFO_HTTP_CODE, @respcode)
          MyDebug("CURL : HTTP ERROR " + Str(respcode) , 8)
          curl_easy_cleanup(curl)
          ProcedureReturn #False
        EndIf
        curl_easy_cleanup(curl)
      Else
        MyDebug("Can't Init CURL", 4)
      EndIf      
    EndIf
    ; Debug "Curl Buffer : " + Str(*Buffer)
    ProcedureReturn *Buffer
  EndProcedure
  
  ;Curl write callback (needed for win32 dll)
  ProcedureC ReceiveHTTPWriteToFileFunction(*ptr, Size.i, NMemB.i, FileHandle.i)
    ProcedureReturn WriteData(FileHandle, *ptr, Size * NMemB)    
  EndProcedure
  
  Procedure.i CurlReceiveHTTPToFile(URL$, DestFileName$, ProxyURL$="", ProxyPort$="", ProxyUser$="", ProxyPassword$="")
    Protected *Buffer, curl.i, Timeout.i, res.i, respcode.l
    Protected FileHandle.i
    MyDebug("CurlReceiveHTTPToFile from " + URL$ + " " + ProxyURL$ + " " + ProxyPort$ + " " + ProxyUser$, 8)
    MyDebug(" to file : " + DestFileName$, 8)
    FileHandle = CreateFile(#PB_Any, DestFileName$)
    If FileHandle And Len(URL$)
      curl  = curl_easy_init()
      If curl
        Timeout = 120
        curl_easy_setopt(curl, #CURLOPT_URL, str2curl(URL$))
        curl_easy_setopt(curl, #CURLOPT_SSL_VERIFYPEER, 0)
        curl_easy_setopt(curl, #CURLOPT_SSL_VERIFYHOST, 0)
        curl_easy_setopt(curl, #CURLOPT_HEADER, 0)   
        curl_easy_setopt(curl, #CURLOPT_FOLLOWLOCATION, 1)
        curl_easy_setopt(curl, #CURLOPT_TIMEOUT, Timeout)
        If Verbose
          curl_easy_setopt(curl, #CURLOPT_VERBOSE, 1)
        EndIf
        curl_easy_setopt(curl, #CURLOPT_FAILONERROR, 1)
        ;curl_easy_setopt(curl, #CURLOPT_CONNECTTIMEOUT, 60)
        If Len(ProxyURL$)
          ;curl_easy_setopt(curl, #CURLOPT_HTTPPROXYTUNNEL, #True)
          If Len(ProxyPort$)
            ProxyURL$ + ":" + ProxyPort$
          EndIf
          MyDebug(ProxyURL$, 8)
          curl_easy_setopt(curl, #CURLOPT_PROXY, str2curl(ProxyURL$))
          If Len(ProxyUser$)
            If Len(ProxyPassword$)
              ProxyUser$ + ":" + ProxyPassword$
            EndIf
            MyDebug(ProxyUser$, 8)
            curl_easy_setopt(curl, #CURLOPT_PROXYUSERPWD, str2curl(ProxyUser$))
          EndIf
        EndIf
        curl_easy_setopt(curl, #CURLOPT_WRITEDATA, FileHandle)
        curl_easy_setopt(curl, #CURLOPT_WRITEFUNCTION, @ReceiveHTTPWriteToFileFunction())
        res = curl_easy_perform(curl)
        If res <> #CURLE_OK
          curl_easy_getinfo(curl, #CURLINFO_HTTP_CODE, @respcode)
          MyDebug("CURL : HTTP ERROR " + Str(respcode) , 8)
          CloseFile(FileHandle)
          curl_easy_cleanup(curl)
          ProcedureReturn #False
        EndIf
        curl_easy_cleanup(curl)
      Else
        MyDebug("Can't init CURL", 8)
      EndIf
      CloseFile(FileHandle)
      ProcedureReturn FileSize(DestFileName$)
    EndIf
    ProcedureReturn #False
  EndProcedure
    
  ;- ***
  
  Procedure TechnicalImagesCreation()
    ;"Loading" image
    Protected LoadingText$ = "Loading"
    Protected NothingText$ = "Nothing"
    PBmap\ImgLoading = CreateImage(#PB_Any, 256, 256) 
    If PBmap\ImgLoading
      StartVectorDrawing(ImageVectorOutput(PBMap\Imgloading)) 
      BeginVectorLayer()
      VectorSourceColor(RGBA(255, 255, 255, 128))
      AddPathBox(0, 0, 256, 256)
      FillPath()
      MovePathCursor(0, 0)
      VectorFont(FontID(PBMap\Font), 256 / 20)
      VectorSourceColor(RGBA(150, 150, 150, 255))
      MovePathCursor(0 + (256 - VectorTextWidth(LoadingText$)) / 2, 0 + (256 - VectorTextHeight(LoadingText$)) / 2)
      DrawVectorText(LoadingText$)
      EndVectorLayer()
      StopVectorDrawing() 
    EndIf
    ;"Nothing" tile
    PBmap\ImgNothing = CreateImage(#PB_Any, 256, 256) 
    If PBmap\ImgNothing
      StartVectorDrawing(ImageVectorOutput(PBMap\ImgNothing)) 
      ;BeginVectorLayer()
      VectorSourceColor(RGBA(220, 230, 255, 255))
      AddPathBox(0, 0, 256, 256)
      FillPath()
      ;MovePathCursor(0, 0)
      ;VectorFont(FontID(PBMap\Font), 256 / 20)
      ;VectorSourceColor(RGBA(150, 150, 150, 255))
      ;MovePathCursor(0 + (256 - VectorTextWidth(NothingText$)) / 2, 0 + (256 - VectorTextHeight(NothingText$)) / 2)
      ;DrawVectorText(NothingText$)
      ;EndVectorLayer()
      StopVectorDrawing() 
    EndIf
  EndProcedure  
  
  ;TODO : best cleaning of the string from bad behaviour
  Procedure.s StringCheck(String.s)
    ProcedureReturn Trim(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(String, Chr(0)), Chr(32)), Chr(39)), Chr(33)), Chr(34)), "@"), "/"), "\"), "$"), "%"))
  EndProcedure
  
  Macro SelBool(Name)
    Select UCase(Value)
      Case "0", "FALSE", "DISABLE"
        PBMap\Options\Name = #False
      Default
        PBMap\Options\Name = #True
    EndSelect
  EndMacro
  
  Procedure.i ColourString2Value(Value.s)
    ;TODO : better string check
    Protected Col.s = RemoveString(Value, " ")
    If Left(Col, 1) = "$"
      Protected r.i, g.i, b.i, a.i = 255
      Select Len(Col)
        Case 4 ;RGB  (eg : "$9BC"
          r = Val("$"+Mid(Col, 2, 1)) : g = Val("$"+Mid(Col, 3, 1)) : b = Val("$"+Mid(Col, 4, 1))
        Case 5 ;RGBA (eg : "$9BC5")
          r = Val("$"+Mid(Col, 2, 1)) : g = Val("$"+Mid(Col, 3, 1)) : b = Val("$"+Mid(Col, 4, 1)) : a = Val("$"+Mid(Col, 5, 1))
        Case 7 ;RRGGBB (eg : "$95B4C2")
          r = Val("$"+Mid(Col, 2, 2)) : g = Val("$"+Mid(Col, 4, 2)) : b = Val("$"+Mid(Col, 6, 2))
        Case 9 ;RRGGBBAA (eg : "$95B4C249")
          r = Val("$"+Mid(Col, 2, 2)) : g = Val("$"+Mid(Col, 4, 2)) : b = Val("$"+Mid(Col, 6, 2)) : a = Val("$"+Mid(Col, 8, 2))
      EndSelect
      ProcedureReturn RGBA(r, g, b, a)
    Else
      ProcedureReturn Val(Value)
    EndIf
  EndProcedure  
  
  Procedure SetOption(Option.s, Value.s)
    Option = StringCheck(Option)
    Select LCase(Option)
      Case "proxy"
        SelBool(Proxy)
      Case "proxyurl"
        PBMap\Options\ProxyURL = Value
      Case "proxyport"        
        PBMap\Options\ProxyPort = Value
      Case "proxyuser"        
        PBMap\Options\ProxyUser = Value
      Case "tilescachepath"
        PBMap\Options\HDDCachePath = Value
      Case "maxmemcache"
        PBMap\Options\MaxMemCache = Val(Value)
      Case "wheelmouserelative"
        SelBool(WheelMouseRelative)
      Case "showdegrees"
        SelBool(ShowDegrees)
      Case "showdebuginfos"
        SelBool(ShowDebugInfos)
      Case "showscale"
        SelBool(ShowScale)
      Case "showmarkers"
        SelBool(ShowMarkers)
      Case "showpointer"
        SelBool(ShowPointer)
      Case "showtrack"
        SelBool(ShowTrack)
      Case "showmarkersnb"
        SelBool(ShowMarkersNb)      
      Case "showmarkerslegend"
        SelBool(ShowMarkersLegend)      
      Case "showtrackkms"
        SelBool(ShowTrackKms)
      Case "strokewidthtrackdefault"
        SelBool(StrokeWidthTrackDefault)
      Case "colourfocus"
        PBMap\Options\ColourFocus = ColourString2Value(Value)
      Case "colourselected"
        PBMap\Options\ColourSelected = ColourString2Value(Value)
      Case "colourtrackdefault"
        PBMap\Options\ColourTrackDefault = ColourString2Value(Value)
    EndSelect
  EndProcedure
  
  ;By default, save options in the user's home directory
  Procedure SaveOptions(PreferencesFile.s = "PBMap.prefs")
    If PreferencesFile = "PBMap.prefs"
      CreatePreferences(GetHomeDirectory() + "PBMap.prefs")      
    Else
      CreatePreferences(PreferencesFile)     
    EndIf
    With PBMap\Options
    PreferenceGroup("PROXY")
    WritePreferenceInteger("Proxy", \Proxy)
    WritePreferenceString("ProxyURL", \ProxyURL)
    WritePreferenceString("ProxyPort", \ProxyPort)
    WritePreferenceString("ProxyUser", \ProxyUser)
    PreferenceGroup("URL")
    WritePreferenceString("DefaultOSMServer", \DefaultOSMServer)
    PreferenceGroup("PATHS")
    WritePreferenceString("TilesCachePath", \HDDCachePath)
    PreferenceGroup("OPTIONS")   
    WritePreferenceInteger("WheelMouseRelative", \WheelMouseRelative)
    WritePreferenceInteger("MaxMemCache", \MaxMemCache)
    WritePreferenceInteger("ShowDegrees", \ShowDegrees)
    WritePreferenceInteger("ShowDebugInfos", \ShowDebugInfos)
    WritePreferenceInteger("ShowScale", \ShowScale)
    WritePreferenceInteger("ShowMarkers", \ShowMarkers)
    WritePreferenceInteger("ShowPointer", \ShowPointer)
    WritePreferenceInteger("ShowTrack", \ShowTrack)
    WritePreferenceInteger("ShowTrackKms", \ShowTrackKms)
    WritePreferenceInteger("ShowMarkersNb", \ShowMarkersNb)
    WritePreferenceInteger("ShowMarkersLegend", \ShowMarkersLegend)
    PreferenceGroup("DRAWING")  
    WritePreferenceInteger("StrokeWidthTrackDefault", \StrokeWidthTrackDefault)
    ;Colours;
    WritePreferenceInteger("ColourFocus", \ColourFocus)
    WritePreferenceInteger("ColourSelected", \ColourSelected)
    WritePreferenceInteger("ColourTrackDefault", \ColourTrackDefault)
    ClosePreferences()
    EndWith
  EndProcedure
  
  Procedure LoadOptions(PreferencesFile.s = "PBMap.prefs")
    If PreferencesFile = "PBMap.prefs"
      OpenPreferences(GetHomeDirectory() + "PBMap.prefs")      
    Else
      OpenPreferences(PreferencesFile)     
    EndIf
    ;Use this to create and customize your preferences file for the first time
    ;     CreatePreferences(GetHomeDirectory() + "PBMap.prefs")
    ;     ;Or this to modify
    ;     ;OpenPreferences(GetHomeDirectory() + "PBMap.prefs")
    ;     ;Or this 
    ;     ;RunProgram("notepad.exe",  GetHomeDirectory() + "PBMap.prefs", GetHomeDirectory())
    ;     PreferenceGroup("PROXY")
    ;     WritePreferenceInteger("Proxy", #True)
    ;     WritePreferenceString("ProxyURL", "myproxy.fr")
    ;     WritePreferenceString("ProxyPort", "myproxyport")
    ;     WritePreferenceString("ProxyUser", "myproxyname")       
    ;     WritePreferenceString("ProxyPass", "myproxypass") ;TODO !Warning! !not encoded!
    ;     ClosePreferences()
    With PBMap\Options
    PreferenceGroup("PROXY")       
    \Proxy              = ReadPreferenceInteger("Proxy", #False)
    If \Proxy
      \ProxyURL         = ReadPreferenceString("ProxyURL", "")  ;InputRequester("ProxyServer", "Do you use a Proxy Server? Then enter the full url:", "")
      \ProxyPort        = ReadPreferenceString("ProxyPort", "") ;InputRequester("ProxyPort"  , "Do you use a specific port? Then enter it", "")
      \ProxyUser        = ReadPreferenceString("ProxyUser", "") ;InputRequester("ProxyUser"  , "Do you use a user name? Then enter it", "")
      \ProxyPassword    = InputRequester("ProxyPass", "Do you use a password ? Then enter it", "") ;TODO
    EndIf
    PreferenceGroup("URL")
    \DefaultOSMServer   = ReadPreferenceString("DefaultOSMServer", "http://tile.openstreetmap.org/")
    
    PreferenceGroup("PATHS")
    \HDDCachePath       = ReadPreferenceString("TilesCachePath", GetTemporaryDirectory())
    PreferenceGroup("OPTIONS")   
    \WheelMouseRelative = ReadPreferenceInteger("WheelMouseRelative", #True)
    \MaxMemCache        = ReadPreferenceInteger("MaxMemCache", 20480) ;20 MiB, about 80 tiles in memory
    \ShowDegrees        = ReadPreferenceInteger("ShowDegrees", #False)
    \ShowDebugInfos     = ReadPreferenceInteger("ShowDebugInfos", #False)
    \ShowScale          = ReadPreferenceInteger("ShowScale", #False)
    \ShowMarkers        = ReadPreferenceInteger("ShowMarkers", #True)
    \ShowPointer        = ReadPreferenceInteger("ShowPointer", #True)
    \ShowTrack          = ReadPreferenceInteger("ShowTrack", #True)
    \ShowTrackKms       = ReadPreferenceInteger("ShowTrackKms", #False)
    \ShowMarkersNb      = ReadPreferenceInteger("ShowMarkersNb", #True)
    \ShowMarkersLegend  = ReadPreferenceInteger("ShowMarkersLegend", #False)
    PreferenceGroup("DRAWING")   
    \StrokeWidthTrackDefault = ReadPreferenceInteger("StrokeWidthTrackDefault", 10)
    PreferenceGroup("COLOURS")
    \ColourFocus        = ReadPreferenceInteger("ColourFocus", RGBA(255, 255, 0, 255))
    \ColourSelected     = ReadPreferenceInteger("ColourSelected", RGBA(225, 225, 0, 255))
    \ColourTrackDefault = ReadPreferenceInteger("ColourTrackDefault", RGBA(0, 255, 0, 150))
    \TimerInterval      = 20
    ClosePreferences()
    EndWith  
  EndProcedure
  
  Procedure.i AddMapServerLayer(LayerName.s, Order.i, ServerURL.s = "http://tile.openstreetmap.org/", TileSize = 256, ZoomMin = 0, ZoomMax = 18)
    Protected *Ptr = AddElement(PBMap\Layers())
    Protected DirName.s = PBMap\Options\HDDCachePath + LayerName + "\"
    If FileSize(DirName) <> -2
      If CreateDirectory(DirName) = #False ; Creates a directory based on the layer name
        Error("Can't create the following cache directory : " + DirName)
      Else
        MyDebug(DirName + " successfully created", 4)
      EndIf
    EndIf
    If *Ptr
      PBMap\Layers()\Name = LayerName
      PBMap\Layers()\Order = Order
      PBMap\Layers()\ServerURL = ServerURL
      SortStructuredList(PBMap\Layers(), #PB_Sort_Ascending, OffsetOf(Layer\Order),TypeOf(Layer\Order))
      ProcedureReturn *Ptr
    Else
      ProcedureReturn #False
    EndIf
  EndProcedure
  
  Procedure DeleteLayer(*Ptr)
    ChangeCurrentElement(PBMap\Layers(), *Ptr)
    DeleteElement(PBMap\Layers())
    FirstElement(PBMap\Layers())
    SortStructuredList(PBMap\Layers(), #PB_Sort_Ascending, OffsetOf(Layer\Order),TypeOf(Layer\Order))
  EndProcedure
  
  Procedure Quit()
    PBMap\Drawing\End = #True
    ;Wait for loading threads to finish nicely. Passed 2 seconds, kills them.
    Protected TimeCounter = ElapsedMilliseconds()
    Repeat
      ForEach PBMap\MemCache\Images()
        If PBMap\MemCache\Images()\Tile <> 0         
          If IsThread(PBMap\MemCache\Images()\Tile\GetImageThread)
            PBMap\MemCache\Images()\Tile\RetryNb = 0
            If ElapsedMilliseconds() - TimeCounter > 2000
              ;Should not occur
              KillThread(PBMap\MemCache\Images()\Tile\GetImageThread)
            EndIf
          Else
            FreeMemory(PBMap\MemCache\Images()\Tile)
            PBMap\MemCache\Images()\Tile = 0
          EndIf
        Else
          DeleteMapElement(PBMap\MemCache\Images())
        EndIf
      Next
      Delay(10)
    Until MapSize(PBMap\MemCache\Images()) = 0 
    curl_global_cleanup()
  EndProcedure
  
  Macro Min(a,b)
    (Bool((a) <= (b)) * (a) + Bool((b) < (a)) * (b))
  EndMacro
  
  Macro Max(a,b)
    (Bool((a) >= (b)) * (a) + Bool((b) > (a)) * (b))
  EndMacro
  
  Procedure.d Distance(x1.d, y1.d, x2.d, y2.d)
    Protected Result.d
    Result = Sqr( (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))
    ProcedureReturn Result
  EndProcedure
  
  ;*** Converts coords to tile.decimal
  ;Warning, structures used in parameters are not tested
  Procedure LatLon2TileXY(*Location.GeographicCoordinates, *Coords.Coordinates, Zoom)
    Protected n.d = Pow(2.0, Zoom)
    Protected LatRad.d = Radian(*Location\Latitude)
    *Coords\x = n * (Mod( *Location\Longitude + 180.0, 360) / 360.0 )
    *Coords\y = n * ( 1.0 - Log(Tan(LatRad) + (1.0/Cos(LatRad))) / #PI ) / 2.0
    MyDebug("Latitude : " + StrD(*Location\Latitude) + " ; Longitude : " + StrD(*Location\Longitude), 5)
    MyDebug("Coords X : " + Str(*Coords\x) + " ;  Y : " + Str(*Coords\y), 5)
  EndProcedure
  
  ;*** Converts tile.decimal to coords
  ;Warning, structures used in parameters are not tested
  Procedure TileXY2LatLon(*Coords.Coordinates, *Location.GeographicCoordinates, Zoom)
    Protected n.d = Pow(2.0, Zoom)
    ;Ensures the longitude to be in the range [-180;180[
    *Location\Longitude  = Mod(Mod(*Coords\x / n * 360.0, 360.0) + 360.0, 360.0) - 180
    *Location\Latitude = Degree(ATan(SinH(#PI * (1.0 - 2.0 * *Coords\y / n))))
    If *Location\Latitude <= -89 
      *Location\Latitude = -89 
    EndIf
    If *Location\Latitude >= 89
      *Location\Latitude = 89 
    EndIf
  EndProcedure
  
  Procedure Pixel2LatLon(*Coords.PixelCoordinates, *Location.GeographicCoordinates, Zoom)
    Protected n.d = PBMap\TileSize * Pow(2.0, Zoom)
    ;Ensures the longitude to be in the range [-180;180[
    *Location\Longitude  = Mod(Mod(*Coords\x / n * 360.0, 360.0) + 360.0, 360.0) - 180
    *Location\Latitude = Degree(ATan(SinH(#PI * (1.0 - 2.0 * *Coords\y / n))))
    If *Location\Latitude <= -89 
      *Location\Latitude = -89 
    EndIf
    If *Location\Latitude >= 89
      *Location\Latitude = 89 
    EndIf
  EndProcedure
  
  ;Ensures the longitude to be in the range [-180;180[
  Procedure.d ClipLongitude(Longitude.d)
    ProcedureReturn Mod(Mod(Longitude + 180, 360.0) + 360.0, 360.0) - 180
  EndProcedure
   
  ;Lat Lon coordinates 2 pixel absolute [0 to 2^Zoom * TileSize [
  Procedure LatLon2Pixel(*Location.GeographicCoordinates, *Pixel.PixelCoordinates, Zoom) 
    Protected tilemax = Pow(2.0, Zoom) * PBMap\TileSize 
    Protected LatRad.d = Radian(*Location\Latitude)
    *Pixel\x = tilemax * (Mod( *Location\Longitude + 180.0, 360) / 360.0 )
    *Pixel\y = tilemax * ( 1.0 - Log(Tan(LatRad) + (1.0/Cos(LatRad))) / #PI ) / 2.0
  EndProcedure   
  
  ;Lat Lon coordinates 2 pixel relative to the center of view
  Procedure LatLon2PixelRel(*Location.GeographicCoordinates, *Pixel.PixelCoordinates, Zoom) 
    Protected tilemax = Pow(2.0, Zoom) * PBMap\TileSize 
    Protected cx.d  = PBMap\Drawing\CenterX
    Protected dpx.d = PBMap\PixelCoordinates\x
    Protected LatRad.d = Radian(*Location\Latitude)
    Protected px.d = tilemax * (Mod( *Location\Longitude + 180.0, 360) / 360.0 )
    Protected py.d = tilemax * ( 1.0 - Log(Tan(LatRad) + (1.0/Cos(LatRad))) / #PI ) / 2.0    
    ;check the x boundaries of the map to adjust the position (coz of the longitude wrapping)
    If dpx - px >= tilemax / 2
      ;Debug "c1"
      *Pixel\x = cx + (px - dpx + tilemax)
    ElseIf px - dpx > tilemax / 2
      ;Debug "c2"
      *Pixel\x = cx + (px - dpx - tilemax)
    ElseIf px - dpx < 0
      ;Debug "c3"
      *Pixel\x = cx - (dpx - px)
    Else
      ;Debug "c0"
      *Pixel\x = cx + (px - dpx) 
    EndIf
    *Pixel\y = PBMap\Drawing\CenterY + (py - PBMap\PixelCoordinates\y) 
  EndProcedure
  
  ; HaversineAlgorithm 
  ; http://andrew.hedges.name/experiments/haversine/
  Procedure.d HaversineInKM(*posA.GeographicCoordinates, *posB.GeographicCoordinates)
    Protected eQuatorialEarthRadius.d = 6378.1370;6372.795477598;
    Protected dlong.d = (*posB\Longitude - *posA\Longitude);
    Protected dlat.d = (*posB\Latitude - *posA\Latitude)   ;
    Protected alpha.d=dlat/2
    Protected beta.d=dlong/2
    Protected a.d = Sin(Radian(alpha)) * Sin(Radian(alpha)) + Cos(Radian(*posA\Latitude)) * Cos(Radian(*posB\Latitude)) * Sin(Radian(beta)) * Sin(Radian(beta)) 
    Protected c.d = ASin(Min(1,Sqr(a)));
    Protected distance.d = 2*eQuatorialEarthRadius * c     
    ProcedureReturn distance                                                                                                        ;
  EndProcedure
  
  Procedure.d HaversineInM(*posA.GeographicCoordinates, *posB.GeographicCoordinates)
    ProcedureReturn (1000 * HaversineInKM(@*posA,@*posB));
  EndProcedure
  
  ; No more used, see LatLon2PixelRel
  Procedure GetPixelCoordFromLocation(*Location.GeographicCoordinates, *Pixel.PixelCoordinates, Zoom) ; TODO to Optimize 
    Protected mapWidth.l    = Pow(2, Zoom + 8)
    Protected mapHeight.l   = Pow(2, Zoom + 8)
    Protected x1.l,y1.l
    x1 = (*Location\Longitude+180)*(mapWidth/360)
    ; convert from degrees To radians
    Protected latRad.d = *Location\Latitude*#PI/180;
    Protected mercN.d = Log(Tan((#PI/4)+(latRad/2)));
    y1     = (mapHeight/2)-(mapWidth*mercN/(2*#PI)) ;
    Protected x2.l, y2.l
    x2 = (PBMap\GeographicCoordinates\Longitude+180)*(mapWidth/360)
    ; convert from degrees To radians
    latRad = PBMap\GeographicCoordinates\Latitude*#PI/180;
    mercN = Log(Tan((#PI/4)+(latRad/2)))        
    y2     = (mapHeight/2)-(mapWidth*mercN/(2*#PI));    
    *Pixel\x=GadgetWidth(PBMap\Gadget)/2  - (x2-x1)
    *Pixel\y=GadgetHeight(PBMap\Gadget)/2 - (y2-y1)
  EndProcedure
  
  Procedure IsInDrawingPixelBoundaries(*Drawing.DrawingParameters, *Position.GeographicCoordinates)
    Protected Pixel.PixelCoordinates
    LatLon2Pixel(*Position, @Pixel, PBMap\Zoom)
    If Pixel\x >= *Drawing\Bounds\BottomLeft\x And Pixel\y <= *Drawing\Bounds\BottomLeft\y And Pixel\x <= *Drawing\Bounds\TopRight\x And Pixel\y >= *Drawing\Bounds\TopRight\y
      ProcedureReturn #True
    Else
      ProcedureReturn #False
    EndIf
  EndProcedure
    
  ;TODO : rotation fix
  Procedure IsInDrawingBoundaries(*Drawing.DrawingParameters, *Position.GeographicCoordinates)
    Protected Lat.d  = *Position\Latitude,                 Lon.d  = *Position\Longitude
    Protected LatNW.d = *Drawing\Bounds\NorthWest\Latitude, LonNW.d = *Drawing\Bounds\NorthWest\Longitude
    Protected LatSE.d = *Drawing\Bounds\SouthEast\Latitude, LonSE.d = *Drawing\Bounds\SouthEast\Longitude
    If Lat >= LatSE And Lat <= LatNW
      If *Drawing\Width >= 360
        ProcedureReturn #True
      Else
        If LonNW < LonSE      
          If Lon >= LonNW And Lon <= LonSE
            ProcedureReturn #True
          Else
            ProcedureReturn #False
          EndIf  
        Else
          If (Lon >= -180 And Lon <= LonSE) Or (Lon >= LonNW And Lon <= 180)
            ProcedureReturn #True
          Else
            ProcedureReturn #False
          EndIf
        EndIf
      EndIf
    Else
      ProcedureReturn #False
    EndIf
  EndProcedure  
   
  ;-*** These are threaded
  Procedure.i GetTileFromHDD(CacheFile.s)
    Protected nImage.i
    If FileSize(CacheFile) > 0
      nImage = LoadImage(#PB_Any, CacheFile)
      If IsImage(nImage)
        MyDebug("Success loading " + CacheFile + " as nImage " + Str(nImage), 3)
        ProcedureReturn nImage  
      Else
        MyDebug("Failed loading " + CacheFile + " as nImage " + Str(nImage) + " -> not an image !", 3)
      EndIf
    Else
      MyDebug("Failed loading " + CacheFile + " -> Size <= 0", 3)
    EndIf
    ProcedureReturn -1
  EndProcedure
  
  Procedure.i GetTileFromWeb(TileURL.s, CacheFile.s)
    Protected *Buffer
    Protected nImage.i = -1
    Protected FileSize.i, timg 
    FileSize = CurlReceiveHTTPToFile(TileURL, CacheFile, PBMap\Options\ProxyURL, PBMap\Options\ProxyPort, PBMap\Options\ProxyUser, PBMap\Options\ProxyPassword)
    If FileSize > 0
      MyDebug("Loaded from web " + TileURL + " as CacheFile " + CacheFile, 3)
      nImage = GetTileFromHDD(CacheFile)
    Else
      MyDebug("Problem loading from web " + TileURL, 3)
    EndIf
    ; **** IMPORTANT NOTICE
    ; I'm (djes) now using Curl only, as this original catchimage/saveimage method is a double operation (uncompress/recompress PNG)
    ; and is modifying the original PNG image which could lead to PNG error (Idle has spent hours debunking the 1 bit PNG bug)
    ; More than that, the original Purebasic Receive library is still not Proxy enabled.
    ;       *Buffer = ReceiveHTTPMemory(TileURL)  ;TODO to thread by using #PB_HTTP_Asynchronous
    ;       If *Buffer
    ;         nImage = CatchImage(#PB_Any, *Buffer, MemorySize(*Buffer))
    ;         If IsImage(nImage)
    ;           If SaveImage(nImage, CacheFile, #PB_ImagePlugin_PNG, 0, 32) ;The 32 is needed !!!!
    ;             MyDebug("Loaded from web " + TileURL + " as CacheFile " + CacheFile, 3)
    ;           Else
    ;             MyDebug("Loaded from web " + TileURL + " but cannot save to CacheFile " + CacheFile, 3)
    ;           EndIf
    ;           FreeMemory(*Buffer)
    ;         Else
    ;           MyDebug("Can't catch image loaded from web " + TileURL, 3)
    ;           nImage = -1
    ;         EndIf
    ;       Else
    ;         MyDebug(" Problem loading from web " + TileURL, 3)
    ;       EndIf
    ; ****
    ProcedureReturn nImage
  EndProcedure
  
  Procedure GetImageThread(*Tile.Tile)
    Protected nImage.i = -1
    Repeat
      nImage = GetTileFromWeb(*Tile\URL, *Tile\CacheFile)
      If nImage <> -1
        MyDebug("Image key : " + *Tile\key + " web image loaded", 3)
        *Tile\RetryNb = 0
      Else 
        MyDebug("Image key : " + *Tile\key + " web image not correctly loaded", 3)
        Delay(5000)
        *Tile\RetryNb - 1
      EndIf
    Until *Tile\RetryNb <= 0
    *Tile\nImage = nImage
    *Tile\RetryNb = -2 ;End of the thread    
    PostEvent(#PB_Event_Gadget, PBMap\Window, PBmap\Gadget, #PB_MAP_TILE_CLEANUP, *Tile) ;To free memory outside the thread
  EndProcedure
  ;-***
  
  Procedure.i GetTile(key.s, URL.s, CacheFile.s)
    ; Try to find the tile in memory cache. If not found, add it, try To load it from the 
    ; HDD, or launch a loading thread, and try again on the next drawing loop.
    Protected img.i = -1
    Protected *timg.ImgMemCach = FindMapElement(PBMap\MemCache\Images(), key)
    If *timg
      MyDebug("Key : " + key + " found in memory cache!", 3)
      img = *timg\nImage
      If img <> -1
        MyDebug("Image : " + img + " found in memory cache!", 3)
        ;*** Cache management
        ; Move the newly used element to the last position of the time stack
        SelectElement(PBMap\MemCache\ImagesTimeStack(), *timg\TimeStackPosition)
        MoveElement(PBMap\MemCache\ImagesTimeStack(), #PB_List_Last)
        ;***
        ProcedureReturn *timg
      EndIf
    Else
      ;PushMapPosition(PBMap\MemCache\Images())
      ;*** Cache management
      ; if cache size exceeds limit, try to delete the oldest tile used (first in the list)
      Protected CacheSize = MapSize(PBMap\MemCache\Images()) * Pow(PBMap\TileSize, 2) * 4 ; Size of a tile = TileSize * TileSize * 4 bytes (RGBA) 
      Protected CacheLimit = PBMap\Options\MaxMemCache * 1024
      MyDebug("Cache size : " + Str(CacheSize/1024) + " / CacheLimit : " + Str(CacheLimit/1024), 4)
      ResetList(PBMap\MemCache\ImagesTimeStack())
      While NextElement(PBMap\MemCache\ImagesTimeStack()) And CacheSize > CacheLimit   
        Protected CacheMapKey.s = PBMap\MemCache\ImagesTimeStack()\MapKey
        Protected Image = PBMap\MemCache\Images(CacheMapKey)\nImage
        If IsImage(Image) ; Check if the image is valid (is a loading thread running ?)
          FreeImage(Image)
          MyDebug("Delete " + CacheMapKey + " As image nb " + Str(Image), 4)
          DeleteMapElement(PBMap\MemCache\Images(), CacheMapKey)
          DeleteElement(PBMap\MemCache\ImagesTimeStack())
          CacheSize = MapSize(PBMap\MemCache\Images()) * Pow(PBMap\TileSize, 2) * 4 ; Size of a tile = TileSize * TileSize * 4 bytes (RGBA) 
        EndIf
      Wend
      LastElement(PBMap\MemCache\ImagesTimeStack())
      ;PopMapPosition(PBMap\MemCache\Images())
      AddMapElement(PBMap\MemCache\Images(), key)
      AddElement(PBMap\MemCache\ImagesTimeStack())
      ;MoveElement(PBMap\MemCache\ImagesTimeStack(), #PB_List_Last)
      PBMap\MemCache\ImagesTimeStack()\MapKey = MapKey(PBMap\MemCache\Images())
      ;***
      MyDebug("Key : " + key + " added in memory cache!", 3)
      *timg = PBMap\MemCache\Images()
      *timg\nImage = -1
    EndIf
    If *timg\Tile = 0 ; Check if a loading thread is not running
      MyDebug("Trying to load from HDD " + CacheFile, 3)
      img = GetTileFromHDD(CacheFile.s)
      If img <> -1
        MyDebug("Key : " + key + " found on HDD", 3)
        *timg\nImage = img
        *timg\Alpha = 256
        ProcedureReturn *timg
      EndIf
      MyDebug("Key : " + key + " not found on HDD", 3)
      ;Launch a new thread
      Protected *NewTile.Tile = AllocateMemory(SizeOf(Tile))
      If *NewTile
        With *NewTile
          *timg\Tile = *NewTile
          *timg\Alpha = 0
          ;*timg\nImage = -1    
          ;New tile parameters
          \key = key
          \URL = URL
          \CacheFile = CacheFile
          \RetryNb = 5
          \nImage = -1         
          MyDebug(" Creating get image thread nb " + Str(\GetImageThread) + " to get " + CacheFile, 3)
          \GetImageThread = CreateThread(@GetImageThread(), *NewTile)
        EndWith  
      Else
        MyDebug(" Error, can't create a new tile loading thread", 3)
      EndIf    
    EndIf
    ProcedureReturn *timg 
  EndProcedure
  
  Procedure DrawTiles(*Drawing.DrawingParameters, Layer)
    Protected x.i, y.i,kq.q
    Protected tx = Int(*Drawing\TileCoordinates\x)          ;Don't forget the Int() !
    Protected ty = Int(*Drawing\TileCoordinates\y)
    Protected nx = *Drawing\CenterX / PBMap\TileSize        ;How many tiles around the point
    Protected ny = *Drawing\CenterY / PBMap\TileSize
    Protected px, py, *timg.ImgMemCach, tilex, tiley, key.s
    Protected URL.s, CacheFile.s
    Protected tilemax = 1<<PBMap\Zoom
    SelectElement(PBMap\Layers(), Layer)
    MyDebug("Drawing tiles")
    For y = - ny - 1 To ny + 1
      For x = - nx - 1 To nx + 1
        px = *Drawing\CenterX + x * PBMap\TileSize - *Drawing\DeltaX
        py = *Drawing\CenterY + y * PBMap\TileSize - *Drawing\DeltaY
        tilex = (tx + x) % tilemax
        If tilex < 0
          tilex + tilemax
        EndIf
        tiley = ty + y 
        If tiley >= 0 And tiley < tilemax
          kq = (PBMap\Zoom << 8) | (tilex << 16) | (tiley << 36)
          key = PBMap\Layers()\Name + Str(kq)
          ; Creates the cache tree based on the OSM tree+Layer : layer/zoom/x/y.png
          ; Creates the sub-directory based on the zoom
          Protected DirName.s = PBMap\Options\HDDCachePath + PBMap\Layers()\Name + "\" + Str(PBMap\Zoom)
          If FileSize(DirName) <> -2
            If CreateDirectory(DirName) = #False 
              Error("Can't create the following cache directory : " + DirName)
            EndIf
          EndIf          
          ; Creates the sub-directory based on x
          DirName.s + "\" + Str(tilex)
          If FileSize(DirName) <> -2
            If CreateDirectory(DirName) = #False 
              Error("Can't create the following cache directory : " + DirName)
            EndIf
          EndIf
          ; Tile cache name based on y
          URL = PBMap\Layers()\ServerURL + Str(PBMap\Zoom) + "/" + Str(tilex) + "/" + Str(tiley) + ".png"   
          CacheFile = DirName + "\" + Str(tiley) + ".png" 
          *timg = GetTile(key, URL, CacheFile)
          If *timg\nImage <> -1  
            MovePathCursor(px, py)
            If *timg\Alpha <= 224
              DrawVectorImage(ImageID(*timg\nImage), *timg\Alpha)
              *timg\Alpha + 32
              PBMap\Redraw = #True
            Else
              DrawVectorImage(ImageID(*timg\nImage), 255)
              *timg\Alpha = 256
            EndIf 
          Else 
            MovePathCursor(px, py)
            DrawVectorImage(ImageID(PBMap\ImgLoading), 255)
          EndIf
        Else
          ;If PBMap\Layers()\Name = ""
          MovePathCursor(px, py)
          DrawVectorImage(ImageID(PBMap\ImgNothing), 255)
          ;EndIf
        EndIf
        If PBMap\Options\ShowDebugInfos
          VectorFont(FontID(PBMap\Font), 16)
          VectorSourceColor(RGBA(0, 0, 0, 80))
          MovePathCursor(px, py)
          DrawVectorText("x:" + Str(tilex)) 
          MovePathCursor(px, py + 16)
          DrawVectorText("y:" + Str(tiley))
        EndIf
      Next
    Next 
  EndProcedure
  
  Procedure DrawPointer(*Drawing.DrawingParameters)
    If PBMap\CallBackMainPointer > 0
      ; @Procedure(X.i, Y.i) to DrawPointer (you must use VectorDrawing lib)
      CallFunctionFast(PBMap\CallBackMainPointer, *Drawing\CenterX, *Drawing\CenterY)
    Else 
      VectorSourceColor(RGBA($FF, 0, 0, $FF))
      MovePathCursor(*Drawing\CenterX, *Drawing\CenterY)
      AddPathLine(-8, -16, #PB_Path_Relative)
      AddPathCircle(8, 0, 8, 180, 0, #PB_Path_Relative)
      AddPathLine(-8, 16, #PB_Path_Relative)
      AddPathCircle(0, -16, 5, 0, 360, #PB_Path_Relative)
      VectorSourceColor(RGBA($FF, 0, 0, $FF))
      FillPath(#PB_Path_Preserve):VectorSourceColor(RGBA($FF, 0, 0, $FF));RGBA(0, 0, 0, 255)) 
      StrokePath(1)
    EndIf  
  EndProcedure
  
  Procedure DrawScale(*Drawing.DrawingParameters,x,y,alpha=80)
    Protected sunit.s 
    Protected Scale.d= 40075*Cos(Radian(PBMap\GeographicCoordinates\Latitude))/Pow(2,PBMap\Zoom) / 2   
    Select PBMap\Options\ScaleUnit 
      Case #SCALE_Nautical
        Scale * 0.539957 
        sunit = " Nm"
      Case #SCALE_KM; 
        sunit = " Km"
    EndSelect
    VectorFont(FontID(PBMap\Font), 10)
    VectorSourceColor(RGBA(0, 0, 0, alpha))
    MovePathCursor(x,y)
    DrawVectorText(StrD(Scale,3)+sunit)
    MovePathCursor(x,y+12) 
    AddPathLine(x+128,y+12)
    StrokePath(1)
  EndProcedure
  
  Procedure DrawDegrees(*Drawing.DrawingParameters, alpha=192) 
    Protected tx, ty, nx,ny,nx1,ny1,x,y,n,cx,dperpixel.d 
    Protected pos1.PixelCoordinates,pos2.PixelCoordinates,Degrees1.GeographicCoordinates,degrees2.GeographicCoordinates 
    Protected realx
;    tx = Int(*Drawing\TileCoordinates\x)
;    ty = Int(*Drawing\TileCoordinates\y)
;      tx = *Drawing\TileCoordinates\x
;      ty = *Drawing\TileCoordinates\y
;      nx = *Drawing\CenterX / PBMap\TileSize ;How many tiles around the point
;      ny = *Drawing\CenterY / PBMap\TileSize
;     *Drawing\Bounds\NorthWest\x = tx-nx-1
;     *Drawing\Bounds\NorthWest\y = ty-ny-1
;     *Drawing\Bounds\SouthEast\x = tx+nx+2 
;     *Drawing\Bounds\SouthEast\y = ty+ny+2 
    ;    Debug "------------------"
    ;TileXY2LatLon(*Drawing\Bounds\NorthWest, @Degrees1, PBMap\Zoom)
    ;TileXY2LatLon(*Drawing\Bounds\SouthEast, @Degrees2, PBMap\Zoom)    
    CopyStructure(*Drawing\Bounds\NorthWest, @Degrees1, GeographicCoordinates)
    CopyStructure(*Drawing\Bounds\SouthEast, @Degrees2, GeographicCoordinates)
    ;ensure we stay positive for the drawing
    nx =  Mod(Mod(Round(Degrees1\Longitude, #PB_Round_Down)-1, 360) + 360, 360)
    ny =          Round(Degrees1\Latitude,  #PB_Round_Up)  +1
    nx1 = Mod(Mod(Round(Degrees2\Longitude, #PB_Round_Up)  +1, 360) + 360, 360)
    ny1 =         Round(Degrees2\Latitude,  #PB_Round_Down)-1 
    Degrees1\Longitude = nx
    Degrees1\Latitude  = ny 
    Degrees2\Longitude = nx1
    Degrees2\Latitude  = ny1
    ;    Debug "NW : " + StrD(Degrees1\Longitude) + " ; NE : " + StrD(Degrees2\Longitude)
    LatLon2PixelRel(@Degrees1, @pos1, PBMap\Zoom)
    LatLon2PixelRel(@Degrees2, @pos2, PBMap\Zoom)
    VectorFont(FontID(PBMap\Font), 10)
    VectorSourceColor(RGBA(0, 0, 0, alpha))    
    ;draw latitudes
    For y = ny1 To ny
      Degrees1\Longitude = nx
      Degrees1\Latitude  = y 
      LatLon2PixelRel(@Degrees1, @pos1, PBMap\Zoom)
      MovePathCursor(pos1\x, pos1\y) 
      AddPathLine(   pos2\x, pos1\y)
      MovePathCursor(10, pos1\y) 
      DrawVectorText(StrD(y, 1))
    Next       
    ;draw longitudes
    x = nx
    Repeat
      Degrees1\Longitude = x
      Degrees1\Latitude  = ny
      LatLon2PixelRel(@Degrees1, @pos1, PBMap\Zoom)
      MovePathCursor(pos1\x, pos1\y)
      AddPathLine(   pos1\x, pos2\y) 
      MovePathCursor(pos1\x,10) 
      DrawVectorText(StrD(Mod(x + 180, 360) - 180, 1))
      x = (x + 1)%360
    Until x = nx1
    StrokePath(1)  
  EndProcedure   
  
  Procedure DrawTrackPointer(x.d, y.d, dist.l)
    Protected color.l
    color=RGBA(0, 0, 0, 255)
    MovePathCursor(x,y)
    AddPathLine(-8,-16,#PB_Path_Relative)
    AddPathLine(16,0,#PB_Path_Relative)
    AddPathLine(-8,16,#PB_Path_Relative)
    VectorSourceColor(color)
    AddPathCircle(x,y-20,14)
    FillPath()
    VectorSourceColor(RGBA(255, 255, 255, 255))
    AddPathCircle(x,y-20,12)
    FillPath()
    VectorFont(FontID(PBMap\Font), 13)
    MovePathCursor(x-VectorTextWidth(Str(dist))/2, y-20-VectorTextHeight(Str(dist))/2)
    VectorSourceColor(RGBA(0, 0, 0, 255))
    DrawVectorText(Str(dist))
  EndProcedure
  
  Procedure DrawTrackPointerFirst(x.d, y.d, dist.l)
    Protected color.l
    color=RGBA(0, 0, 0, 255)
    MovePathCursor(x,y)
    AddPathLine(-9,-17,#PB_Path_Relative)
    AddPathLine(17,0,#PB_Path_Relative)
    AddPathLine(-9,17,#PB_Path_Relative)
    VectorSourceColor(color)
    AddPathCircle(x,y-24,16)
    FillPath()
    VectorSourceColor(RGBA(255, 0, 0, 255))
    AddPathCircle(x,y-24,14)
    FillPath()
    VectorFont(FontID(PBMap\Font), 14)
    MovePathCursor(x-VectorTextWidth(Str(dist))/2, y-24-VectorTextHeight(Str(dist))/2)
    VectorSourceColor(RGBA(0, 0, 0, 255))
    DrawVectorText(Str(dist))
  EndProcedure
  
  Procedure DeleteTrack(*Ptr)
    If *Ptr 
      ChangeCurrentElement(PBMap\TracksList(), *Ptr)
      DeleteElement(PBMap\TracksList())
    EndIf
  EndProcedure
  
  Procedure DeleteSelectedTracks()
    ForEach PBMap\TracksList()
      If PBMap\TracksList()\Selected
        DeleteElement(PBMap\TracksList())
        PBMap\Redraw = #True
      EndIf
    Next
  EndProcedure
  
  Procedure ClearTracks()
    ClearList(PBMap\TracksList())
    PBMap\Redraw = #True  
  EndProcedure
  
  Procedure SetTrackColour(*Ptr, Colour.i)
    If *Ptr 
      ChangeCurrentElement(PBMap\TracksList(), *Ptr)
      PBMap\TracksList()\Colour = Colour
      PBMap\Redraw = #True
    EndIf
  EndProcedure
  
  Procedure  DrawTracks(*Drawing.DrawingParameters)
    Protected Pixel.PixelCoordinates
    Protected Location.GeographicCoordinates
    Protected km.f, memKm.i
    With PBMap\TracksList()
      ;Trace Track
      If ListSize(PBMap\TracksList()) > 0
        BeginVectorLayer()
        ForEach PBMap\TracksList()
          If ListSize(\Track()) > 0
            ;Check visibility
            \Visible = #False
            ForEach \Track()
              If IsInDrawingPixelBoundaries(*Drawing, @PBMap\TracksList()\Track())
                \Visible = #True
                Break
              EndIf
            Next
            If \Visible
              ;Draw tracks
              ForEach \Track()
                LatLon2PixelRel(@PBMap\TracksList()\Track(),  @Pixel, PBMap\Zoom)
                If ListIndex(\Track()) = 0
                  MovePathCursor(Pixel\x, Pixel\y)
                Else
                  AddPathLine(Pixel\x, Pixel\y)    
                EndIf
              Next
              ;           \BoundingBox\x = PathBoundsX()
              ;           \BoundingBox\y = PathBoundsY()
              ;           \BoundingBox\w = PathBoundsWidth()
              ;           \BoundingBox\h = PathBoundsHeight()
              If \Focus
                VectorSourceColor(PBMap\Options\ColourFocus)
              ElseIf \Selected
                VectorSourceColor(PBMap\Options\ColourSelected)
              Else
                VectorSourceColor(\Colour)
              EndIf
              StrokePath(\StrokeWidth, #PB_Path_RoundEnd|#PB_Path_RoundCorner)
            EndIf  
          EndIf
        Next
        EndVectorLayer()
        ;Draw distances
        If PBMap\Options\ShowTrackKms And PBMap\Zoom > 10
          BeginVectorLayer()
          ForEach PBMap\TracksList()
            If \Visible
              km = 0 : memKm = -1
              ForEach PBMap\TracksList()\Track()
                ;Test Distance
                If ListIndex(\Track()) = 0
                  Location\Latitude = \Track()\Latitude
                  Location\Longitude = \Track()\Longitude 
                Else 
                  km = km + HaversineInKM(@Location, @PBMap\TracksList()\Track())
                  Location\Latitude = \Track()\Latitude
                  Location\Longitude = \Track()\Longitude 
                EndIf
                LatLon2PixelRel(@PBMap\TracksList()\Track(), @Pixel, PBMap\Zoom)
                If Int(km) <> memKm
                  memKm = Int(km)
                  RotateCoordinates(Pixel\x, Pixel\y, -PBMap\Angle)
                  If Int(km) = 0
                    DrawTrackPointerFirst(Pixel\x , Pixel\y, Int(km))
                  Else
                    DrawTrackPointer(Pixel\x , Pixel\y, Int(km))
                  EndIf
                  RotateCoordinates(Pixel\x, Pixel\y, PBMap\Angle)
                EndIf
              Next
            EndIf
          Next
          EndVectorLayer()
        EndIf
      EndIf
    EndWith
  EndProcedure
  
  Procedure.i LoadGpxFile(file.s)
    If LoadXML(0, file.s)
      Protected Message.s
      If XMLStatus(0) <> #PB_XML_Success
        Message = "Error in the XML file:" + Chr(13)
        Message + "Message: " + XMLError(0) + Chr(13)
        Message + "Line: " + Str(XMLErrorLine(0)) + "   Character: " + Str(XMLErrorPosition(0))
        MessageRequester("Error", Message)
      EndIf
      Protected *MainNode,*subNode,*child,child.l
      *MainNode=MainXMLNode(0)
      *MainNode=XMLNodeFromPath(*MainNode,"/gpx/trk/trkseg")
      Protected *NewTrack.Tracks = AddElement(PBMap\TracksList())
      PBMap\TracksList()\StrokeWidth = PBMap\Options\StrokeWidthTrackDefault
      PBMap\TracksList()\Colour      = PBMap\Options\ColourTrackDefault
      For child = 1 To XMLChildCount(*MainNode)
        *child = ChildXMLNode(*MainNode, child)
        AddElement(*NewTrack\Track())
        If ExamineXMLAttributes(*child)
          While NextXMLAttribute(*child)
            Select XMLAttributeName(*child)
              Case "lat"
                *NewTrack\Track()\Latitude=ValD(XMLAttributeValue(*child))
              Case "lon"
                *NewTrack\Track()\Longitude=ValD(XMLAttributeValue(*child))
            EndSelect
          Wend
        EndIf
      Next 
      ZoomToTracks(LastElement(PBMap\TracksList())) ; <-To center the view, and zoom on the tracks  
      ProcedureReturn *NewTrack  
    EndIf
  EndProcedure

  
  Procedure ClearMarkers()
    ClearList(PBMap\Markers())
    PBMap\Redraw = #True  
  EndProcedure
  
  Procedure DeleteMarker(*Ptr)
    If *Ptr 
      ChangeCurrentElement(PBMap\Markers(), *Ptr)
      DeleteElement(PBMap\Markers())
      PBMap\Redraw = #True
    EndIf
  EndProcedure
  
  Procedure DeleteSelectedMarkers()
    ForEach PBMap\Markers()
      If PBMap\Markers()\Selected
        DeleteElement(PBMap\Markers())
        PBMap\Redraw = #True
      EndIf
    Next
  EndProcedure
  
  Procedure.i AddMarker(Latitude.d, Longitude.d, Identifier.s = "", Legend.s = "", Color.l=-1, CallBackPointer.i = -1)
    Protected *Ptr = AddElement(PBMap\Markers())
    If *Ptr 
      PBMap\Markers()\GeographicCoordinates\Latitude = Latitude
      PBMap\Markers()\GeographicCoordinates\Longitude = ClipLongitude(Longitude)
      PBMap\Markers()\Identifier = Identifier
      PBMap\Markers()\Legend = Legend
      PBMap\Markers()\Color = Color
      PBMap\Markers()\CallBackPointer = CallBackPointer
      PBMap\Redraw = #True
      ProcedureReturn *Ptr
    EndIf
  EndProcedure
  
  ;-*** Marker Edit
  Procedure MarkerIdentifierChange()
    Protected *Marker.Marker = GetGadgetData(EventGadget())
    If GetGadgetText(EventGadget()) <> *Marker\Identifier
      *Marker\Identifier = GetGadgetText(EventGadget())
    EndIf
  EndProcedure  
  Procedure MarkerLegendChange()
    Protected *Marker.Marker = GetGadgetData(EventGadget())
    If GetGadgetText(EventGadget()) <> *Marker\Legend
      *Marker\Legend = GetGadgetText(EventGadget())
    EndIf
  EndProcedure  
  Procedure MarkerEditCloseWindow()
    ForEach PBMap\Markers()
      If PBMap\Markers()\EditWindow = EventWindow()
        PBMap\Markers()\EditWindow = 0
      EndIf
    Next
    CloseWindow(EventWindow())  
  EndProcedure
  Procedure MarkerEdit(*Marker.Marker)
    If *Marker\EditWindow = 0 ;Check that this marker has no already opened window
      Protected WindowMarkerEdit = OpenWindow(#PB_Any, WindowX(PBMap\Window) + WindowWidth(PBMap\Window) / 2 - 150, WindowY(PBMap\Window)+ WindowHeight(PBMap\Window) / 2 + 50, 300, 100, "Marker Edit", #PB_Window_SystemMenu | #PB_Window_TitleBar)
      StickyWindow(WindowMarkerEdit, #True) 
      TextGadget(#PB_Any, 2, 2, 80, 25, gettext("Identifier"))
      TextGadget(#PB_Any, 2, 27, 80, 25, gettext("Legend"))
      Protected StringIdentifier = StringGadget(#PB_Any, 84, 2, 120, 25, *Marker\Identifier) : SetGadgetData(StringIdentifier, *Marker)
      Protected EditorLegend = EditorGadget(#PB_Any, 84, 27, 210, 70) : SetGadgetText(EditorLegend, *Marker\Legend) : SetGadgetData(EditorLegend, *Marker)
      *Marker\EditWindow = WindowMarkerEdit
      BindGadgetEvent(StringIdentifier, @MarkerIdentifierChange(), #PB_EventType_Change)
      BindGadgetEvent(EditorLegend, @MarkerLegendChange(), #PB_EventType_Change)
      BindEvent(#PB_Event_CloseWindow, @MarkerEditCloseWindow(), WindowMarkerEdit)  
    Else
      SetActiveWindow(*Marker\EditWindow)
    EndIf
  EndProcedure
  ;-***

  Procedure DrawMarker(x.i, y.i, Nb.i, *Marker.Marker)
    Protected Text.s
    VectorSourceColor(*Marker\Color)
    MovePathCursor(x, y)
    AddPathLine(-8, -16, #PB_Path_Relative)
    AddPathCircle(8, 0, 8, 180, 0, #PB_Path_Relative)
    AddPathLine(-8, 16, #PB_Path_Relative)
    ;FillPath(#PB_Path_Preserve) 
    ;ClipPath(#PB_Path_Preserve)
    AddPathCircle(0, -16, 5, 0, 360, #PB_Path_Relative)
    VectorSourceColor(*Marker\Color)
    FillPath(#PB_Path_Preserve)
    If *Marker\Focus
      VectorSourceColor(PBMap\Options\ColourFocus)
      StrokePath(3)
    ElseIf *Marker\Selected
      VectorSourceColor(PBMap\Options\ColourSelected)
      StrokePath(4)
    Else
      VectorSourceColor(*Marker\Color)
      StrokePath(1)
    EndIf
    If PBMap\Options\ShowMarkersNb
      If *Marker\Identifier = ""
        Text.s = Str(Nb)
      Else
        Text.s = *Marker\Identifier
      EndIf
      VectorFont(FontID(PBMap\Font), 13)
      MovePathCursor(x - VectorTextWidth(Text) / 2, y)
      VectorSourceColor(RGBA(0, 0, 0, 255))
      DrawVectorText(Text)
    EndIf
    If PBMap\Options\ShowMarkersLegend And *Marker\Legend <> ""
      VectorFont(FontID(PBMap\Font), 13)
      ;dessin d'un cadre avec fond transparent
      Protected Height = VectorParagraphHeight(*Marker\Legend, 100, 100)
      Protected Width.l
      If Height < 20 ; une ligne
        Width = VectorTextWidth(*Marker\Legend)
      Else
        Width = 100
      EndIf
      AddPathBox(x - (Width / 2), y - 30 - Height, Width, Height)
      VectorSourceColor(RGBA(168, 255, 255, 100))
      FillPath()
      AddPathBox(x - (Width / 2), y - 30 - Height, Width, Height)
      VectorSourceColor(RGBA(36, 36, 255, 100))
      StrokePath(2)
      MovePathCursor(x - 50, y - 30 - Height)
      VectorSourceColor(RGBA(0, 0, 0, 255))
      DrawVectorParagraph(*Marker\Legend, 100, Height, #PB_VectorParagraph_Center)
    EndIf  
  EndProcedure
    
  ; Draw all markers
  Procedure DrawMarkers(*Drawing.DrawingParameters)
    Protected Pixel.PixelCoordinates
    ForEach PBMap\Markers()
      If IsInDrawingPixelBoundaries(*Drawing, @PBMap\Markers()\GeographicCoordinates)
        LatLon2PixelRel(@PBMap\Markers()\GeographicCoordinates, @Pixel, PBMap\Zoom)
        RotateCoordinates(Pixel\x, Pixel\y, -PBMap\Angle)
        If PBMap\Markers()\CallBackPointer > 0
          CallFunctionFast(PBMap\Markers()\CallBackPointer, Pixel\x, Pixel\y, PBMap\Markers()\Focus, PBMap\Markers()\Selected)
        Else
          DrawMarker(Pixel\x, Pixel\y, ListIndex(PBMap\Markers()), @PBMap\Markers())
        EndIf
        RotateCoordinates(Pixel\x, Pixel\y, PBMap\Angle)
      EndIf 
    Next
  EndProcedure 
  
  Procedure DrawDebugInfos(*Drawing.DrawingParameters)
    ; Display how many images in cache
    VectorFont(FontID(PBMap\Font), 16)
    VectorSourceColor(RGBA(0, 0, 0, 80))
    MovePathCursor(50,50)
    DrawVectorText(Str(MapSize(PBMap\MemCache\Images())))
    MovePathCursor(50,70)
    Protected ThreadCounter = 0
    ForEach PBMap\MemCache\Images()
      If PBMap\MemCache\Images()\Tile <> 0
        If IsThread(PBMap\MemCache\Images()\Tile\GetImageThread)
          ThreadCounter + 1
        EndIf
      EndIf
    Next
    DrawVectorText(Str(ThreadCounter))    
    MovePathCursor(50,90)
    DrawVectorText(Str(PBMap\Zoom))
    MovePathCursor(50,110)
    DrawVectorText(StrD(*Drawing\Bounds\NorthWest\Latitude) + "," + StrD(*Drawing\Bounds\NorthWest\Longitude))  
    MovePathCursor(50,130)
    DrawVectorText(StrD(*Drawing\Bounds\SouthEast\Latitude) + "," + StrD(*Drawing\Bounds\SouthEast\Longitude))  
  EndProcedure
  
  Procedure DrawOSMCopyright(*Drawing.DrawingParameters)
    Protected Text.s = "© OpenStreetMap contributors"
    VectorFont(FontID(PBMap\Font), 12)
    VectorSourceColor(RGBA(0, 0, 0, 80))
    MovePathCursor(GadgetWidth(PBMAP\Gadget) - VectorTextWidth(Text), GadgetHeight(PBMAP\Gadget) - 20)
    DrawVectorText(Text)
  EndProcedure
  
  ;-*** Main drawing
  Procedure Drawing()
    Protected *Drawing.DrawingParameters = @PBMap\Drawing
    Protected PixelCenter.PixelCoordinates
    Protected Px.d, Py.d,a, ts = PBMap\TileSize, nx, ny
    Protected NW.Coordinates, SE.Coordinates
    PBMap\Dirty = #False
    PBMap\Redraw = #False
    ;*** Precalc some values
    *Drawing\CenterX = GadgetWidth(PBMap\Gadget) / 2
    *Drawing\CenterY = GadgetHeight(PBMap\Gadget) / 2
    *Drawing\GeographicCoordinates\Latitude = PBMap\GeographicCoordinates\Latitude
    *Drawing\GeographicCoordinates\Longitude = PBMap\GeographicCoordinates\Longitude
    LatLon2TileXY(*Drawing\GeographicCoordinates, *Drawing\TileCoordinates, PBMap\Zoom)
    LatLon2Pixel(*Drawing\GeographicCoordinates, @PixelCenter, PBMap\Zoom)
    ; Pixel shift, aka position in the tile
    Px = *Drawing\TileCoordinates\x 
    Py = *Drawing\TileCoordinates\y
    *Drawing\DeltaX = Px * ts - (Int(Px) * ts) ;Don't forget the Int() !
    *Drawing\DeltaY = Py * ts - (Int(Py) * ts)
    ;Drawing boundaries  
;      nx = *Drawing\CenterX / ts ;How many tiles around the point
;      ny = *Drawing\CenterY / ts
;      NW\x = Px - nx - 1
;      NW\y = Py - ny - 1
;      SE\x = Px + nx + 2 
;      SE\y = Py + ny + 2
;      TileXY2LatLon(@NW, *Drawing\Bounds\NorthWest, PBMap\Zoom)
;      TileXY2LatLon(@SE, *Drawing\Bounds\SouthEast, PBMap\Zoom)
     ;TODO : rotation fix
    nx = PixelCenter\x - *Drawing\CenterX 
    ny = PixelCenter\y + *Drawing\CenterY
    StartVectorDrawing(CanvasVectorOutput(PBMap\Gadget))
    RotateCoordinates(PixelCenter\x, PixelCenter\y, PBMap\Angle)
    *Drawing\Bounds\BottomLeft\x = ConvertCoordinateX(nx, ny, #PB_Coordinate_Device, #PB_Coordinate_User)
    *Drawing\Bounds\BottomLeft\y = ConvertCoordinateY(nx, ny, #PB_Coordinate_Device, #PB_Coordinate_User)
    nx + GadgetWidth(PBMap\Gadget)
    ny - GadgetHeight(PBMap\Gadget)
    *Drawing\Bounds\TopRight\x = ConvertCoordinateX(nx, ny, #PB_Coordinate_Device, #PB_Coordinate_User)
    *Drawing\Bounds\TopRight\y = ConvertCoordinateY(nx, ny, #PB_Coordinate_Device, #PB_Coordinate_User)
    StopVectorDrawing()
    Pixel2LatLon(*Drawing\Bounds\BottomLeft, *Drawing\Bounds\SouthEast, PBMap\Zoom)
    Pixel2LatLon(*Drawing\Bounds\TopRight, *Drawing\Bounds\NorthWest, PBMap\Zoom)
;      Debug *Drawing\Bounds\NorthWest\Latitude
;      Debug *Drawing\Bounds\NorthWest\Longitude
;      Debug *Drawing\Bounds\SouthEast\Latitude
;      Debug *Drawing\Bounds\SouthEast\Longitude
    ;*Drawing\Width = (SE\x / Pow(2, PBMap\Zoom) * 360.0) - (NW\x / Pow(2, PBMap\Zoom) * 360.0) ;Calculus without clipping
    ;*Drawing\Height = *Drawing\Bounds\NorthWest\Latitude - *Drawing\Bounds\SouthEast\Latitude
    ;***
    ; Main drawing stuff
    StartVectorDrawing(CanvasVectorOutput(PBMap\Gadget))
    ;Main rotation
    RotateCoordinates(*Drawing\CenterX, *Drawing\CenterY, PBMap\Angle)
    ;Clearscreen
    VectorSourceColor(RGBA(150, 150, 150, 255))
    FillVectorOutput()
    ;TODO add in layers of tiles ;this way we can cache them as 0 base 1.n layers 
    ; such as for openseamap tiles which are overlaid. not that efficent from here though.
    ForEach PBMap\Layers()
      DrawTiles(*Drawing, ListIndex(PBMap\Layers())) 
    Next   
    If PBMap\Options\ShowDegrees And PBMap\Zoom > 2
      DrawDegrees(*Drawing, 192)    
    EndIf    
    If PBMap\Options\ShowTrack
      DrawTracks(*Drawing)
    EndIf
    If PBMap\Options\ShowMarkers
      DrawMarkers(*Drawing)
    EndIf
    ResetCoordinates()        
    If PBMap\Options\ShowPointer
      DrawPointer(*Drawing)
    EndIf
    If PBMap\Options\ShowDebugInfos
      DrawDebugInfos(*Drawing)
    EndIf
    If PBMap\Options\ShowScale
      DrawScale(*Drawing, 10, GadgetHeight(PBMAP\Gadget) - 20, 192)
    EndIf
    DrawOSMCopyright(*Drawing)
    StopVectorDrawing()
  EndProcedure
  
  Procedure Refresh()
    PBMap\Redraw = #True
    ;Drawing()
  EndProcedure
  
  Procedure.d Pixel2Lon(x)
    Protected NewX.d = (PBMap\PixelCoordinates\x - GadgetWidth(PBMap\Gadget) / 2 + x) / PBMap\TileSize
    Protected n.d = Pow(2.0, PBMap\Zoom)
    ; double mod is to ensure the longitude to be in the range [-180;180[
    ProcedureReturn Mod(Mod(NewX / n * 360.0, 360.0) + 360.0, 360.0) - 180
  EndProcedure
  
  Procedure.d Pixel2Lat(y)
    Protected NewY.d = (PBMap\PixelCoordinates\y - GadgetHeight(PBMap\Gadget) / 2 + y) / PBMap\TileSize
    Protected n.d = Pow(2.0, PBMap\Zoom)
    ProcedureReturn Degree(ATan(SinH(#PI * (1.0 - 2.0 * NewY / n))))
  EndProcedure
  
  Procedure.d MouseLongitude()
    Protected MouseX.d = (PBMap\PixelCoordinates\x - GadgetWidth(PBMap\Gadget) / 2 + GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseX)) / PBMap\TileSize
    Protected n.d = Pow(2.0, PBMap\Zoom)
    ; double mod is to ensure the longitude to be in the range [-180;180[
    ProcedureReturn Mod(Mod(MouseX / n * 360.0, 360.0) + 360.0, 360.0) - 180
  EndProcedure
  
  Procedure.d MouseLatitude()
    Protected MouseY.d = (PBMap\PixelCoordinates\y - GadgetHeight(PBMap\Gadget) / 2 + GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseY)) / PBMap\TileSize
    Protected n.d = Pow(2.0, PBMap\Zoom)
    ProcedureReturn Degree(ATan(SinH(#PI * (1.0 - 2.0 * MouseY / n))))
  EndProcedure
  
  Procedure SetLocation(latitude.d, longitude.d, Zoom = -1, Mode.i = #PB_Absolute)
    Select Mode
      Case #PB_Absolute
        PBMap\GeographicCoordinates\Latitude = latitude
        PBMap\GeographicCoordinates\Longitude = longitude
        If Zoom <> -1 
          PBMap\Zoom = Zoom
        EndIf
      Case #PB_Relative
        PBMap\GeographicCoordinates\Latitude  + latitude
        PBMap\GeographicCoordinates\Longitude + longitude
        If Zoom <> -1 
          PBMap\Zoom + Zoom
        EndIf    
    EndSelect
    PBMap\GeographicCoordinates\Longitude = ClipLongitude(PBMap\GeographicCoordinates\Longitude)
    If PBMap\GeographicCoordinates\Latitude < -89 
      PBMap\GeographicCoordinates\Latitude = -89 
    EndIf
    If PBMap\GeographicCoordinates\Latitude > 89
      PBMap\GeographicCoordinates\Latitude = 89 
    EndIf
    If PBMap\Zoom > PBMap\ZoomMax : PBMap\Zoom = PBMap\ZoomMax : EndIf
    If PBMap\Zoom < PBMap\ZoomMin : PBMap\Zoom = PBMap\ZoomMin : EndIf
    LatLon2TileXY(@PBMap\GeographicCoordinates, @PBMap\Drawing\TileCoordinates, PBMap\Zoom)
    ; Convert X, Y in tile.decimal into real pixels
    PBMap\PixelCoordinates\x = PBMap\Drawing\TileCoordinates\x * PBMap\TileSize
    PBMap\PixelCoordinates\y = PBMap\Drawing\TileCoordinates\y * PBMap\TileSize 
    PBMap\Redraw = #True
    If PBMap\CallBackLocation > 0
      CallFunctionFast(PBMap\CallBackLocation, @PBMap\GeographicCoordinates)
    EndIf 
  EndProcedure
  
  Procedure ZoomToArea(MinY.d, MaxY.d, MinX.d, MaxX.d)
    ;Source => http://gis.stackexchange.com/questions/19632/how-to-calculate-the-optimal-zoom-level-to-display-two-or-more-points-on-a-map
    ;bounding box in long/lat coords (x=long, y=lat)
    Protected DeltaX.d=MaxX-MinX                            ;assumption ! In original code DeltaX have no source
    Protected centerX.d=MinX+DeltaX/2                       ; assumption ! In original code CenterX have no source
    Protected paddingFactor.f= 1.2                          ;paddingFactor: this can be used to get the "120%" effect ThomM refers to. Value of 1.2 would get you the 120%.
    Protected ry1.d = Log((Sin(Radian(MinY)) + 1) / Cos(Radian(MinY)))
    Protected ry2.d = Log((Sin(Radian(MaxY)) + 1) / Cos(Radian(MaxY)))
    Protected ryc.d = (ry1 + ry2) / 2                                 
    Protected centerY.d = Degree(ATan(SinH(ryc)))                     
    Protected resolutionHorizontal.d = DeltaX / GadgetWidth(PBMap\Gadget)
    Protected vy0.d = Log(Tan(#PI*(0.25 + centerY/360)));
    Protected vy1.d = Log(Tan(#PI*(0.25 + MaxY/360)))   ;
    Protected viewHeightHalf.d = GadgetHeight(PBMap\Gadget)/2;
    Protected zoomFactorPowered.d = viewHeightHalf / (40.7436654315252*(vy1 - vy0))
    Protected resolutionVertical.d = 360.0 / (zoomFactorPowered * PBMap\TileSize)    
    If resolutionHorizontal<>0 And resolutionVertical<>0
      Protected resolution.d = Max(resolutionHorizontal, resolutionVertical)* paddingFactor
      Protected zoom.d = Log(360 / (resolution * PBMap\TileSize))/Log(2)
      Protected lon.d = centerX;
      Protected lat.d = centerY;
      SetLocation(lat, lon, Round(zoom,#PB_Round_Down))
    Else
      SetLocation(PBMap\GeographicCoordinates\Latitude, PBMap\GeographicCoordinates\Longitude, 15)
    EndIf
  EndProcedure
  
  Procedure  ZoomToTracks(*Tracks.Tracks)
    Protected MinY.d, MaxY.d, MinX.d, MaxX.d
    If ListSize(*Tracks\Track()) > 0
      With *Tracks\Track()
        FirstElement(*Tracks\Track())
        MinX = \Longitude : MaxX = MinX : MinY = \Latitude : MaxY = MinY
        ForEach *Tracks\Track()
          If \Longitude < MinX
            MinX = \Longitude
          EndIf
          If \Longitude > MaxX
            MaxX = \Longitude
          EndIf
          If \Latitude < MinY
            MinY = \Latitude
          EndIf
          If \Latitude > MaxY
            MaxY = \Latitude
          EndIf
        Next 
        ZoomToArea(MinY.d, MaxY.d, MinX.d, MaxX.d)
      EndWith
    EndIf
  EndProcedure
  
  Procedure SetZoom(Zoom.i, mode.i = #PB_Relative)
    Select mode
      Case #PB_Relative
        PBMap\Zoom = PBMap\Zoom + zoom  
      Case #PB_Absolute
        PBMap\Zoom = zoom
    EndSelect
    If PBMap\Zoom > PBMap\ZoomMax : PBMap\Zoom = PBMap\ZoomMax  : ProcedureReturn : EndIf
    If PBMap\Zoom < PBMap\ZoomMin : PBMap\Zoom = PBMap\ZoomMin  : ProcedureReturn : EndIf
    LatLon2TileXY(@PBMap\GeographicCoordinates, @PBMap\Drawing\TileCoordinates, PBMap\Zoom)
    ; Convert X, Y in tile.decimal into real pixels
    PBMap\PixelCoordinates\X = PBMap\Drawing\TileCoordinates\x * PBMap\TileSize
    PBMap\PixelCoordinates\Y = PBMap\Drawing\TileCoordinates\y * PBMap\TileSize
    ; First drawing
    PBMap\Redraw = #True
    If PBMap\CallBackLocation > 0
      CallFunctionFast(PBMap\CallBackLocation, @PBMap\GeographicCoordinates)
    EndIf 
  EndProcedure
  
  Procedure SetAngle(Angle.d, Mode = #PB_Absolute) 
    If Mode = #PB_Absolute 
      PBmap\Angle = Angle  
    Else 
      PBMap\Angle + Angle 
      PBMap\Angle = Mod(PBMap\Angle,360)
    EndIf
    PBMap\Redraw = #True
  EndProcedure

  Procedure SetCallBackLocation(CallBackLocation.i)
    PBMap\CallBackLocation = CallBackLocation
  EndProcedure
  
  Procedure SetCallBackMainPointer(CallBackMainPointer.i)
    PBMap\CallBackMainPointer = CallBackMainPointer
  EndProcedure
  
  Procedure SetMapScaleUnit(ScaleUnit.i = PBMAP::#SCALE_KM)
    PBMap\Options\ScaleUnit = ScaleUnit
    PBMap\Redraw = #True
    ;Drawing()
  EndProcedure   
  
  ; User mode
  ; #MODE_DEFAULT = 0 -> "Hand" (move map) and move objects
  ; #MODE_HAND    = 1 -> Hand only
  ; #MODE_SELECT  = 2 -> Move objects only
  ; #MODE_EDIT    = 3 -> Create objects
  Procedure SetMode(Mode.i = #MODE_DEFAULT)
    PBMap\Mode = Mode  
  EndProcedure
  
  Procedure.i GetMode()
    ProcedureReturn PBMap\Mode
  EndProcedure
  
  ;Zoom on x, y pixel position from the center
  Procedure ZoomOnPixel(x, y, zoom)
    ;*** First : Zoom
    PBMap\Zoom + zoom
    If PBMap\Zoom > PBMap\ZoomMax : PBMap\Zoom = PBMap\ZoomMax : ProcedureReturn : EndIf
    If PBMap\Zoom < PBMap\ZoomMin : PBMap\Zoom = PBMap\ZoomMin : ProcedureReturn : EndIf
    LatLon2Pixel(@PBMap\GeographicCoordinates, @PBMap\PixelCoordinates, PBMap\Zoom)
    If Zoom = 1
      PBMap\PixelCoordinates\x + x
      PBMap\PixelCoordinates\y + y
    ElseIf zoom = -1
      PBMap\PixelCoordinates\x - x/2
      PBMap\PixelCoordinates\y - y/2
    EndIf
    Pixel2LatLon(@PBMap\PixelCoordinates, @PBMap\GeographicCoordinates, PBMap\Zoom)
    ; Start drawing
    PBMap\Redraw = #True
    ; If CallBackLocation send Location To function
    If PBMap\CallBackLocation > 0
      CallFunctionFast(PBMap\CallBackLocation, @PBMap\GeographicCoordinates)
    EndIf      
  EndProcedure  
  
  ;Zoom on x, y position relative to the canvas gadget
  Procedure ZoomOnPixelRel(x, y, zoom)
    Protected CenterX = GadgetWidth(PBMap\Gadget) / 2
    Protected CenterY = GadgetHeight(PBMap\Gadget) / 2
    x - CenterX 
    y - CenterY
    ZoomOnPixel(x, y, zoom)
  EndProcedure  
  
  ;Go to x, y position relative to the canvas gadget left up
  Procedure GotoPixelRel(x, y)
    Protected CenterX = GadgetWidth(PBMap\Gadget) / 2
    Protected CenterY = GadgetHeight(PBMap\Gadget) / 2
    x - CenterX 
    y - CenterY
    LatLon2Pixel(@PBMap\GeographicCoordinates, @PBMap\PixelCoordinates, PBMap\Zoom)
    PBMap\PixelCoordinates\x + x
    PBMap\PixelCoordinates\y + y
    Pixel2LatLon(@PBMap\PixelCoordinates, @PBMap\GeographicCoordinates, PBMap\Zoom)
    ; Start drawing
    PBMap\Redraw = #True
    ; If CallBackLocation send Location to function
    If PBMap\CallBackLocation > 0
      CallFunctionFast(PBMap\CallBackLocation, @PBMap\GeographicCoordinates)
    EndIf      
  EndProcedure  
  
  ;Go to x, y position relative to the canvas gadget
  Procedure GotoPixel(x, y)
    PBMap\PixelCoordinates\x = x
    PBMap\PixelCoordinates\y = y
    Pixel2LatLon(@PBMap\PixelCoordinates, @PBMap\GeographicCoordinates, PBMap\Zoom)
    ; Start drawing
    PBMap\Redraw = #True
    ; If CallBackLocation send Location to function
    If PBMap\CallBackLocation > 0
      CallFunctionFast(PBMap\CallBackLocation, @PBMap\GeographicCoordinates)
    EndIf      
  EndProcedure  
  
  Procedure.d GetLatitude()
    ProcedureReturn PBMap\GeographicCoordinates\Latitude
  EndProcedure
  
  Procedure.d GetLongitude()
    ProcedureReturn PBMap\GeographicCoordinates\Longitude
  EndProcedure
  
  Procedure.i GetZoom()
    ProcedureReturn PBMap\Zoom
  EndProcedure
  
  Procedure.d GetAngle()
    ProcedureReturn PBMap\Angle
  EndProcedure
  
  Procedure NominatimGeoLocationQuery(Address.s, *ReturnPosition.GeographicCoordinates = 0)
    Protected Query.s = "http://nominatim.openstreetmap.org/search/" + 
                        URLEncoder(Address) + 
                        ;"Unter%20den%20Linden%201%20Berlin" +
    "?format=json&addressdetails=0&polygon=0&limit=1"
    Protected JSONFileName.s = PBMap\Options\HDDCachePath + "nominatimresponse.json"
    ;    Protected *Buffer = CurlReceiveHTTPToMemory("http://nominatim.openstreetmap.org/search/Unter%20den%20Linden%201%20Berlin?format=json&addressdetails=1&limit=1&polygon_svg=1", PBMap\Options\ProxyURL, PBMap\Options\ProxyPort, PBMap\Options\ProxyUser, PBMap\Options\ProxyPassword)
    ;     Debug *Buffer
    ;     Debug MemorySize(*Buffer)
    ;     Protected JSon.s = PeekS(*Buffer, MemorySize(*Buffer), #PB_UTF8)
    Protected Size.i = CurlReceiveHTTPToFile(Query, JSONFileName, PBMap\Options\ProxyURL, PBMap\Options\ProxyPort, PBMap\Options\ProxyUser, PBMap\Options\ProxyPassword)
    If LoadJSON(0, JSONFileName) = 0
      ;Demivec's code
      MyDebug( JSONErrorMessage() + " at position " +
               JSONErrorPosition() + " in line " +
               JSONErrorLine() + " of JSON web Data", 1)
    ElseIf JSONArraySize(JSONValue(0)) > 0
      Protected object_val = GetJSONElement(JSONValue(0), 0)
      Protected object_box = GetJSONMember(object_val, "boundingbox")
      Protected bbox.BoundingBox
      bbox\SouthEast\Latitude = ValD(GetJSONString(GetJSONElement(object_box, 0)))
      bbox\NorthWest\Latitude = ValD(GetJSONString(GetJSONElement(object_box, 1)))
      bbox\NorthWest\Longitude = ValD(GetJSONString(GetJSONElement(object_box, 2)))
      bbox\SouthEast\Longitude = ValD(GetJSONString(GetJSONElement(object_box, 3)))
      Protected lat.s = GetJSONString(GetJSONMember(object_val, "lat"))
      Protected lon.s = GetJSONString(GetJSONMember(object_val, "lon"))
      If *ReturnPosition <> 0
        *ReturnPosition\Latitude = ValD(lat)
        *ReturnPosition\Longitude = ValD(lon)
      EndIf
      If lat<> "" And lon <> "" 
        ZoomToArea(bbox\SouthEast\Latitude, bbox\NorthWest\Latitude, bbox\NorthWest\Longitude, bbox\SouthEast\Longitude)
        ;SetLocation(Position\Latitude, Position\Longitude)
      EndIf
    EndIf
  EndProcedure

  Procedure CanvasEvents()
    Protected CanvasMouseX.d, CanvasMouseY.d, MouseX.d, MouseY.d
    Protected MarkerCoords.PixelCoordinates, *Tile.Tile, MapWidth = Pow(2, PBMap\Zoom) * PBMap\TileSize
    Protected key.s, Touch.i
    Protected Pixel.PixelCoordinates
    Static CtrlKey
    PBMap\Moving = #False
    MouseX = GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseX) - PBMap\Drawing\CenterX
    MouseY = GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseY) - PBMap\Drawing\CenterY
    StartVectorDrawing(CanvasVectorOutput(PBMap\Gadget))
    RotateCoordinates(0, 0, PBMap\Angle)
    CanvasMouseX = ConvertCoordinateX(MouseX, MouseY, #PB_Coordinate_Device, #PB_Coordinate_User)
    CanvasMouseY = ConvertCoordinateY(MouseX, MouseY, #PB_Coordinate_Device, #PB_Coordinate_User)
    StopVectorDrawing()
    Select EventType()
      Case #PB_EventType_Focus
        PBMap\Drawing\CenterX = GadgetWidth(PBMap\Gadget) / 2
        PBMap\Drawing\CenterY = GadgetHeight(PBMap\Gadget) / 2
      Case #PB_EventType_KeyUp  
        Select GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_Key)
          Case #PB_Shortcut_Delete
            DeleteSelectedMarkers()
            DeleteSelectedTracks()
        EndSelect
        PBMap\Redraw = #True
        If GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_Modifiers)&#PB_Canvas_Control = 0
          CtrlKey = #False
        EndIf
      Case #PB_EventType_KeyDown
        With PBMap\Markers()
        Select GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_Key)
          Case #PB_Shortcut_Left
            ForEach PBMap\Markers()
              If \Selected
                \GeographicCoordinates\Longitude = ClipLongitude( \GeographicCoordinates\Longitude - 10* 360 / Pow(2, PBMap\Zoom + 8))
              EndIf
            Next            
          Case #PB_Shortcut_Up        
            ForEach PBMap\Markers()
              If \Selected
                \GeographicCoordinates\Latitude + 10* 360 / Pow(2, PBMap\Zoom + 8)
              EndIf
            Next            
          Case #PB_Shortcut_Right     
            ForEach PBMap\Markers()
              If \Selected
                \GeographicCoordinates\Longitude = ClipLongitude( \GeographicCoordinates\Longitude + 10* 360 / Pow(2, PBMap\Zoom + 8))
              EndIf
            Next            
          Case #PB_Shortcut_Down
            ForEach PBMap\Markers()
              If \Selected
                \GeographicCoordinates\Latitude - 10* 360 / Pow(2, PBMap\Zoom + 8)
              EndIf
            Next            
        EndSelect
        EndWith
        PBMap\Redraw = #True
        If GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_Modifiers)&#PB_Canvas_Control <> 0
          CtrlKey = #True
        EndIf
      Case #PB_EventType_LeftDoubleClick
        LatLon2Pixel(@PBMap\GeographicCoordinates, @PBMap\PixelCoordinates, PBMap\Zoom)
        MouseX = PBMap\PixelCoordinates\x  + CanvasMouseX
        MouseY = PBMap\PixelCoordinates\y  + CanvasMouseY
        ;Clip MouseX to the map range (in X, the map is infinite)
        MouseX = Mod(Mod(MouseX, MapWidth) + MapWidth, MapWidth)
        Touch = #False
        ;Check if the mouse touch a marker
        ForEach PBMap\Markers()              
          LatLon2Pixel(@PBMap\Markers()\GeographicCoordinates, @MarkerCoords, PBMap\Zoom)
          If Distance(MarkerCoords\x, MarkerCoords\y, MouseX, MouseY) < 8
            If PBMap\Mode = #MODE_DEFAULT Or PBMap\Mode = #MODE_SELECT
              ;Jump to the marker
              Touch = #True
              SetLocation(PBMap\Markers()\GeographicCoordinates\Latitude, PBMap\Markers()\GeographicCoordinates\Longitude)
            ElseIf PBMap\Mode = #MODE_EDIT
              ;Edit the legend
              MarkerEdit(@PBMap\Markers())
            EndIf
            Break
          EndIf
        Next
        If Not Touch
          GotoPixel(MouseX, MouseY)
        EndIf
      Case #PB_EventType_MouseWheel
        If PBMap\Options\WheelMouseRelative
          ;Relative zoom (centered on the mouse)
          ZoomOnPixel(CanvasMouseX, CanvasMouseY, GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_WheelDelta))
        Else
          ;Absolute zoom (centered on the center of the map)
          SetZoom(GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_WheelDelta), #PB_Relative)
        EndIf        
      Case #PB_EventType_LeftButtonDown
        ;LatLon2Pixel(@PBMap\GeographicCoordinates, @PBMap\PixelCoordinates, PBMap\Zoom)
        ;Mem cursor Coord
        PBMap\MoveStartingPoint\x = CanvasMouseX
        PBMap\MoveStartingPoint\y = CanvasMouseY
        ;Clip MouseX to the map range (in X, the map is infinite)
        PBMap\MoveStartingPoint\x = Mod(Mod(PBMap\MoveStartingPoint\x, MapWidth) + MapWidth, MapWidth)
        If PBMap\Mode = #MODE_DEFAULT Or PBMap\Mode = #MODE_SELECT
          PBMap\EditMarker = #False
          ;Check if we select marker(s)
          ForEach PBMap\Markers()                   
            If CtrlKey = #False
              PBMap\Markers()\Selected = #False ;If no CTRL key, deselect everything and select only the focused marker
            EndIf
            If PBMap\Markers()\Focus
              PBMap\Markers()\Selected = #True
              PBMap\EditMarker = #True;ListIndex(PBMap\Markers())  
              PBMap\Markers()\Focus = #False
            EndIf
          Next
          ;Check if we select track(s)
          ForEach PBMap\TracksList()                   
            If CtrlKey = #False
              PBMap\TracksList()\Selected = #False ;If no CTRL key, deselect everything and select only the focused track
            EndIf
            If PBMap\TracksList()\Focus
              PBMap\TracksList()\Selected = #True
              PBMap\TracksList()\Focus = #False
            EndIf
          Next
        EndIf
      Case #PB_EventType_MouseMove
        PBMap\Moving = #True
        ; Drag
        If PBMap\MoveStartingPoint\x <> - 1
          MouseX = CanvasMouseX - PBMap\MoveStartingPoint\x
          MouseY = CanvasMouseY - PBMap\MoveStartingPoint\y
          PBMap\MoveStartingPoint\x = CanvasMouseX
          PBMap\MoveStartingPoint\y = CanvasMouseY
          ;Move selected markers
          If PBMap\EditMarker And (PBMap\Mode = #MODE_DEFAULT Or PBMap\Mode = #MODE_SELECT)
            ForEach PBMap\Markers()
              If PBMap\Markers()\Selected
                LatLon2Pixel(@PBMap\Markers()\GeographicCoordinates, @MarkerCoords, PBMap\Zoom)
                MarkerCoords\x + MouseX
                MarkerCoords\y + MouseY
                Pixel2LatLon(@MarkerCoords, @PBMap\Markers()\GeographicCoordinates, PBMap\Zoom)
              EndIf
            Next
          ElseIf PBMap\Mode = #MODE_DEFAULT Or PBMap\Mode = #MODE_HAND
            ;Move map only
            LatLon2Pixel(@PBMap\GeographicCoordinates, @PBMap\PixelCoordinates, PBMap\Zoom) ;This line could be removed as the coordinates don't have to change but I want to be sure we rely only on geographic coordinates
            PBMap\PixelCoordinates\x - MouseX
            ;Ensures that pixel position stay in the range [0..2^Zoom*PBMap\TileSize[ coz of the wrapping of the map
            PBMap\PixelCoordinates\x = Mod(Mod(PBMap\PixelCoordinates\x, MapWidth) + MapWidth, MapWidth)
            PBMap\PixelCoordinates\y - MouseY
            Pixel2LatLon(@PBMap\PixelCoordinates, @PBMap\GeographicCoordinates, PBMap\Zoom)
            ;If CallBackLocation send Location to function
            If PBMap\CallBackLocation > 0
              CallFunctionFast(PBMap\CallBackLocation, @PBMap\GeographicCoordinates)
            EndIf 
          EndIf
          PBMap\Redraw = #True
        Else
          ; Touch test
          LatLon2Pixel(@PBMap\GeographicCoordinates, @PBMap\PixelCoordinates, PBMap\Zoom)
          MouseX = PBMap\PixelCoordinates\x + CanvasMouseX 
          MouseY = PBMap\PixelCoordinates\y + CanvasMouseY 
          ;Clip MouseX to the map range (in X, the map is infinite)
          MouseX = Mod(Mod(MouseX, MapWidth) + MapWidth, MapWidth)
          If PBMap\Mode = #MODE_DEFAULT Or PBMap\Mode = #MODE_SELECT Or PBMap\Mode = #MODE_EDIT
            ;Check if mouse touch markers
            ForEach PBMap\Markers()              
              LatLon2Pixel(@PBMap\Markers()\GeographicCoordinates, @MarkerCoords, PBMap\Zoom)
              If Distance(MarkerCoords\x, MarkerCoords\y, MouseX, MouseY) < 8
                PBMap\Markers()\Focus = #True
                PBMap\Redraw = #True
              ElseIf PBMap\Markers()\Focus
                ;If CtrlKey = #False
                PBMap\Markers()\Focus = #False
                PBMap\Redraw = #True
              EndIf
            Next
            ;Check if mouse touch tracks           
            With PBMap\TracksList()
              ;Trace Track
              If ListSize(PBMap\TracksList()) > 0
                ForEach PBMap\TracksList()
                  If ListSize(\Track()) > 0
                    If \Visible
                      StartVectorDrawing(CanvasVectorOutput(PBMap\Gadget))
                      RotateCoordinates(PBMap\Drawing\CenterX, PBMap\Drawing\CenterY, PBMap\Angle)
                      ;Simulate tracks drawing
                      ForEach \Track()
                        LatLon2Pixel(@PBMap\TracksList()\Track(),  @Pixel, PBMap\Zoom)
                        If ListIndex(\Track()) = 0
                          MovePathCursor(Pixel\x, Pixel\y)
                        Else
                          AddPathLine(Pixel\x, Pixel\y)    
                        EndIf
                      Next
                      If IsInsideStroke(MouseX, MouseY, \StrokeWidth)
                        \Focus = #True
                        PBMap\Redraw = #True
                      ElseIf \Focus
                        \Focus = #False
                        PBMap\Redraw = #True
                      EndIf
                      StopVectorDrawing()
                    EndIf  
                  EndIf
                Next
              EndIf
            EndWith
          EndIf
        EndIf
      Case #PB_EventType_LeftButtonUp
        PBMap\MoveStartingPoint\x = - 1
        PBMap\Redraw = #True
      Case #PB_MAP_REDRAW
        Debug "Redraw"
        PBMap\Redraw = #True
      Case #PB_MAP_RETRY
        Debug "Reload"
        PBMap\Redraw = #True
      Case #PB_MAP_TILE_CLEANUP
        *Tile = EventData() 
        key = *Tile\key
        ;After a Web tile loading thread, clean the tile structure memory and set the image nb in the cache
        ;avoid to have threads accessing vars (and avoid mutex), see GetImageThread()
        Protected timg = PBMap\MemCache\Images(key)\Tile\nImage ;Get this new tile image nb
        PBMap\MemCache\Images(key)\nImage = timg                ;store it in the cache using the key
        FreeMemory(PBMap\MemCache\Images(key)\Tile)             ;free the data needed for the thread
        PBMap\MemCache\Images(key)\Tile = 0                     ;clear the data ptr
        PBMap\Redraw = #True
    EndSelect
  EndProcedure
  
  Procedure TimerEvents()
    ;Redraw at regular intervals
    If EventTimer() = PBMap\Timer And (PBMap\Redraw Or PBMap\Dirty)
      Drawing()
    EndIf    
  EndProcedure 
  
  ; Could be called directly to attach our map to an existing canvas
  Procedure BindMapGadget(Gadget.i)
    PBMap\Gadget = Gadget
    BindGadgetEvent(PBMap\Gadget, @CanvasEvents())
    AddWindowTimer(PBMap\Window, PBMap\Timer, PBMap\Options\TimerInterval)
    BindEvent(#PB_Event_Timer, @TimerEvents())
    PBMap\Drawing\CenterX = GadgetWidth(PBMap\Gadget) / 2
    PBMap\Drawing\CenterX = GadgetHeight(PBMap\Gadget) / 2
  EndProcedure
  
  ; Creates a canvas and attach our map
  Procedure MapGadget(Gadget.i, X.i, Y.i, Width.i, Height.i)
    If Gadget = #PB_Any
      PBMap\Gadget = CanvasGadget(PBMap\Gadget, X, Y, Width, Height, #PB_Canvas_Keyboard) ;#PB_Canvas_Keyboard has to be set for mousewheel to work on windows
    Else
      PBMap\Gadget = Gadget
      CanvasGadget(PBMap\Gadget, X, Y, Width, Height, #PB_Canvas_Keyboard) 
    EndIf
    BindMapGadget(PBMap\Gadget)
  EndProcedure
  
  Procedure InitPBMap(Window)
    Protected Result.i
    If Verbose
      OpenConsole()
    EndIf
    PBMap\ZoomMin = 0
    PBMap\ZoomMax = 18
    PBMap\MoveStartingPoint\x = - 1
    PBMap\TileSize = 256
    PBMap\Dirty = #False
    PBMap\EditMarker = #False
    PBMap\Font = LoadFont(#PB_Any, "Arial", 20, #PB_Font_Bold)
    PBMap\Window = Window
    PBMap\Timer = 1
    PBMap\Mode = #MODE_DEFAULT
    LoadOptions()
    If PBMap\Options\DefaultOSMServer <> "" 
      AddMapServerLayer("OSM", 1, PBMap\Options\DefaultOSMServer)
    EndIf
    curl_global_init(#CURL_GLOBAL_WIN32)
    TechnicalImagesCreation()
    SetLocation(0, 0)
  EndProcedure
  
EndModule

;-**** Example of application ****
CompilerIf #PB_Compiler_IsMainFile 
  InitNetwork()
  
  Enumeration
    #Window_0
    #Map
    #Gdt_Left
    #Gdt_Right
    #Gdt_Up
    #Gdt_Down
    #Gdt_RotateLeft
    #Gdt_RotateRight
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
    #Gdt_AddMarker
    #Gdt_AddOpenseaMap
    #Gdt_Degrees
    #Gdt_EditMode
    #TextGeoLocationQuery
    #StringGeoLocationQuery
  EndEnumeration
  
  ;Menu events
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
  
  ;This callback demonstration procedure will receive relative coords from canvas
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
  
  Procedure MainPointer(x.i, y.i)
    VectorSourceColor(RGBA(255, 255,255, 255)) : AddPathCircle(x, y,32) : StrokePath(1)
    VectorSourceColor(RGBA(0, 0, 0, 255)) : AddPathCircle(x, y, 29):StrokePath(2)
  EndProcedure
  
  Procedure ResizeAll()
    ResizeGadget(#Map,10,10,WindowWidth(#Window_0)-198,WindowHeight(#Window_0)-59)
    ResizeGadget(#Text_1,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_Left, WindowWidth(#Window_0) - 150 ,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_Right,WindowWidth(#Window_0) -  90 ,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_RotateLeft, WindowWidth(#Window_0) - 150 ,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_RotateRight,WindowWidth(#Window_0) -  90 ,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_Up,   WindowWidth(#Window_0) - 120 ,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_Down, WindowWidth(#Window_0) - 120 ,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Text_2,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Button_4,WindowWidth(#Window_0)-150,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Button_5,WindowWidth(#Window_0)-100,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Text_3,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#StringLatitude,WindowWidth(#Window_0)-120,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#StringLongitude,WindowWidth(#Window_0)-120,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Text_4,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_AddMarker,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_LoadGpx,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_AddOpenseaMap,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_Degrees,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_EditMode,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#TextGeoLocationQuery,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#StringGeoLocationQuery,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    PBMap::Refresh()
  EndProcedure
  
  ;- MAIN TEST
  If OpenWindow(#Window_0, 260, 225, 700, 571, "PBMap",  #PB_Window_SystemMenu | #PB_Window_MinimizeGadget | #PB_Window_TitleBar | #PB_Window_ScreenCentered | #PB_Window_SizeGadget)
    
    LoadFont(0, "Arial", 12)
    LoadFont(1, "Arial", 12, #PB_Font_Bold)
    LoadFont(2, "Arial", 8)
    
    TextGadget(#Text_1, 530, 50, 60, 15, "Movements")
    ButtonGadget(#Gdt_RotateLeft,  550, 070, 30, 30, "LRot")  : SetGadgetFont(#Gdt_RotateLeft, FontID(2)) 
    ButtonGadget(#Gdt_RotateRight, 610, 070, 30, 30, "RRot")  : SetGadgetFont(#Gdt_RotateRight, FontID(2)) 
    ButtonGadget(#Gdt_Left,  550, 100, 30, 30, Chr($25C4))  : SetGadgetFont(#Gdt_Left, FontID(0)) 
    ButtonGadget(#Gdt_Right, 610, 100, 30, 30, Chr($25BA))  : SetGadgetFont(#Gdt_Right, FontID(0)) 
    ButtonGadget(#Gdt_Up,    580, 070, 30, 30, Chr($25B2))  : SetGadgetFont(#Gdt_Up, FontID(0)) 
    ButtonGadget(#Gdt_Down,  580, 130, 30, 30, Chr($25BC))  : SetGadgetFont(#Gdt_Down, FontID(0)) 
    TextGadget(#Text_2, 530, 160, 60, 15, "Zoom")
    ButtonGadget(#Button_4, 550, 180, 50, 30, " + ")        : SetGadgetFont(#Button_4, FontID(1)) 
    ButtonGadget(#Button_5, 600, 180, 50, 30, " - ")        : SetGadgetFont(#Button_5, FontID(1)) 
    TextGadget(#Text_3, 530, 230, 50, 15, "Latitude ")
    StringGadget(#StringLatitude, 580, 230, 90, 20, "")
    TextGadget(#Text_4, 530, 250, 50, 15, "Longitude ")
    StringGadget(#StringLongitude, 580, 250, 90, 20, "")
    ButtonGadget(#Gdt_AddMarker, 530, 280, 150, 30, "Add Marker")
    ButtonGadget(#Gdt_LoadGpx, 530, 310, 150, 30, "Load GPX")    
    ButtonGadget(#Gdt_AddOpenseaMap, 530, 340, 150, 30, "Show/Hide OpenSeaMap", #PB_Button_Toggle)
    ButtonGadget(#Gdt_Degrees, 530, 370, 150, 30, "Show/Hide Degrees", #PB_Button_Toggle)
    ButtonGadget(#Gdt_EditMode, 530, 400, 150, 30, "Edit mode ON/OFF", #PB_Button_Toggle)
    TextGadget(#TextGeoLocationQuery, 530, 435, 150, 15, "Enter an address")
    StringGadget(#StringGeoLocationQuery, 530, 450, 150, 20, "")
    SetActiveGadget(#StringGeoLocationQuery)
    AddKeyboardShortcut(#Window_0, #PB_Shortcut_Return, #MenuEventGeoLocationStringEnter)
    ;*** TODO : code to remove when the SetActiveGadget(-1) will be fixed
    CompilerIf #PB_Compiler_OS = #PB_OS_Linux
      Define Dummy = ButtonGadget(#PB_Any, 0, 0, 1, 1, "Dummy") 
      HideGadget(Dummy, 1) 
    CompilerElse
      Define Dummy = -1
    CompilerEndIf
    ;***
    Define Event.i, Gadget.i, Quit.b = #False
    Define pfValue.d
    Define OpenSeaMap = 0, Degrees = 1
    Define *Track
    
    ;Our main gadget
    PBMap::InitPBMap(#Window_0)
    PBMap::SetOption("ShowDegrees", "0") : Degrees = 0
    PBMap::SetOption("ShowDebugInfos", "0")
    PBMap::SetOption("ShowScale", "1")
    PBMap::SetOption("ShowMarkersLegend", "1")
    PBMap::SetOption("ShowTrackKms", "1")        
    PBMap::SetOption("ColourFocus", "$FFFF00AA")    
    PBMap::MapGadget(#Map, 10, 10, 512, 512)
    PBMap::SetCallBackMainPointer(@MainPointer())                   ; To change the main pointer (center of the view)
    PBMap::SetCallBackLocation(@UpdateLocation())                   ; To obtain realtime coordinates
    PBMap::SetLocation(-36.81148, 175.08634,12)                     ; Change the PBMap coordinates
    PBMAP::SetMapScaleUnit(PBMAP::#SCALE_KM)                        ; To change the scale unit
    PBMap::AddMarker(49.0446828398, 2.0349812508, "", "", -1, @MyMarker())  ; To add a marker with a customised GFX
    
    Repeat
      Event = WaitWindowEvent()
      Select Event
        Case #PB_Event_CloseWindow : Quit = 1
        Case #PB_Event_Gadget ;{
          Gadget = EventGadget()
          Select Gadget
            Case #Gdt_Up
              PBMap::SetLocation(10* 360 / Pow(2, PBMap::GetZoom() + 8), 0, 0, #PB_Relative)
            Case #Gdt_Down
              PBMap::SetLocation(10* -360 / Pow(2, PBMap::GetZoom() + 8), 0, 0, #PB_Relative)
            Case #Gdt_Left
              PBMap::SetLocation(0, 10* -360 / Pow(2, PBMap::GetZoom() + 8), 0, #PB_Relative)
            Case #Gdt_Right
              PBMap::SetLocation(0, 10* 360 / Pow(2, PBMap::GetZoom() + 8), 0, #PB_Relative)
            Case #Gdt_RotateLeft
              PBMAP::SetAngle(-5,#PB_Relative) 
              PBMap::Refresh()
            Case #Gdt_RotateRight
              PBMAP::SetAngle(5,#PB_Relative) 
              PBMap::Refresh()
            Case #Button_4
              PBMap::SetZoom(1)
            Case #Button_5
              PBMap::SetZoom( - 1)
            Case #Gdt_LoadGpx
              *Track = PBMap::LoadGpxFile(OpenFileRequester("Choose a file to load", "", "Gpx|*.gpx", 0))
              PBMap::SetTrackColour(*Track, RGBA(Random(255), Random(255), Random(255), 128))
            Case #StringLatitude, #StringLongitude
              Select EventType()
                Case #PB_EventType_Focus
                  AddKeyboardShortcut(#Window_0, #PB_Shortcut_Return, #MenuEventLonLatStringEnter)
                Case #PB_EventType_LostFocus
                  RemoveKeyboardShortcut(#Window_0, #PB_Shortcut_Return)
              EndSelect
            Case #Gdt_AddMarker
              PBMap::AddMarker(ValD(GetGadgetText(#StringLatitude)), ValD(GetGadgetText(#StringLongitude)), "", "Test", RGBA(Random(255), Random(255), Random(255), 255))
            Case #Gdt_AddOpenseaMap
              If OpenSeaMap = 0
                OpenSeaMap = PBMap::AddMapServerLayer("OpenSeaMap", 2, "http://t1.openseamap.org/seamark/") ; Add a special osm overlay map on layer nb 2
                SetGadgetState(#Gdt_AddOpenseaMap, 1)
              Else
                PBMap::DeleteLayer(OpenSeaMap)
                OpenSeaMap = 0
                SetGadgetState(#Gdt_AddOpenseaMap, 0)
              EndIf
              PBMAP::Refresh()
            Case #Gdt_Degrees
              Degrees = 1 - Degrees
              PBMap::SetOption("ShowDegrees", Str(Degrees))
              PBMap::Refresh()
              SetGadgetState(#Gdt_Degrees, Degrees)
            Case #Gdt_EditMode
              If PBMap::GetMode() <> PBMap::#MODE_EDIT
                PBMap::SetMode(PBMap::#MODE_EDIT)
                SetGadgetState(#Gdt_EditMode, 1)
              Else
                PBMap::SetMode(PBMap::#MODE_DEFAULT)
                SetGadgetState(#Gdt_EditMode, 0)
              EndIf
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
        ;Receive "enter" key events
        Select EventMenu()
          Case #MenuEventGeoLocationStringEnter
            If GetGadgetText(#StringGeoLocationQuery) <> ""
              PBMap::NominatimGeoLocationQuery(GetGadgetText(#StringGeoLocationQuery))
              PBMap::Refresh()
            EndIf
            ;*** TODO : code to change when the SetActiveGadget(-1) will be fixed
            SetActiveGadget(Dummy)
            ;***
          Case  #MenuEventLonLatStringEnter
            PBMap::SetLocation(ValD(GetGadgetText(#StringLatitude)), ValD(GetGadgetText(#StringLongitude)))                     ; Change the PBMap coordinates
            PBMap::Refresh()
        EndSelect
    EndSelect
    Until Quit = #True
    
    PBMap::Quit()
  EndIf
  
CompilerEndIf


; IDE Options = PureBasic 5.50 (Windows - x64)
; CursorPosition = 1523
; FirstLine = 1495
; Folding = -----------------
; EnableThread
; EnableXP
; EnableUnicode