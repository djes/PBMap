; ******************************************************************** 
; Program:           PBMap
; Description:       Permits the use of tiled maps like 
;                    OpenStreetMap in a handy PureBASIC module
; Author:            Thyphoon, djes, Idle, yves86
; Date:              July, 2017
; License:           PBMap : Free, unrestricted, credit 
;                    appreciated but not required.
; OSM :              see http://www.openstreetmap.org/copyright
; Note:              Please share improvement !
; Thanks:            Progi1984
; ******************************************************************** 

CompilerIf #PB_Compiler_Thread = #False
  MessageRequester("Warning !", "You must enable ThreadSafe support in compiler options", #PB_MessageRequester_Ok )
  End
CompilerEndIf 

EnableExplicit

InitNetwork()
UsePNGImageDecoder()
UseJPEGImageDecoder()
UsePNGImageEncoder()
UseJPEGImageEncoder()

;- Module declaration

DeclareModule PBMap  
  
  #PBMAPNAME = "PBMap"
  #PBMAPVERSION = "0.9"
  #USERAGENT = #PBMAPNAME + "/" + #PBMAPVERSION + " (https://github.com/djes/PBMap)"
  
  CompilerIf #PB_Compiler_OS = #PB_OS_Linux
    #Red = 255
  CompilerEndIf
  
  #SCALE_NAUTICAL = 1 
  #SCALE_KM = 0 
  
  #MODE_DEFAULT = 0
  #MODE_HAND = 1
  #MODE_SELECT = 2
  #MODE_EDIT = 3
  
  #MARKER_EDIT_EVENT = #PB_Event_FirstCustomValue
  
  #PB_MAP_REDRAW = #PB_EventType_FirstCustomValue + 1 
  #PB_MAP_RETRY  = #PB_EventType_FirstCustomValue + 2
  #PB_MAP_TILE_CLEANUP = #PB_EventType_FirstCustomValue + 3
  
  ;-*** Public structures
  Structure GeographicCoordinates
    Longitude.d
    Latitude.d
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
  ;***
  
  Declare SelectPBMap(Gadget.i)                    ; Could be used to have multiple PBMaps in one window
  Declare SetDebugLevel(Level.i)
  Declare SetOption(Option.s, Value.s)
  Declare.s GetOption(Option.s)
  Declare LoadOptions(PreferencesFile.s = "PBMap.prefs")
  Declare SaveOptions(PreferencesFile.s = "PBMap.prefs")
  Declare.i AddOSMServerLayer(LayerName.s, Order.i, ServerURL.s = "http://tile.openstreetmap.org/")
  Declare.i AddHereServerLayer(LayerName.s, Order.i, APP_ID.s = "", APP_CODE.s = "", ServerURL.s = "aerial.maps.api.here.com", path.s = "/maptile/2.1/", ressource.s = "maptile", id.s = "newest", scheme.s = "satellite.day", format.s = "jpg", lg.s = "eng", lg2.s = "eng", param.s = "")
  Declare.i AddGeoServerLayer(LayerName.s, Order.i, ServerLayerName.s, ServerURL.s = "http://localhost:8080/", path.s = "geowebcache/service/gmaps", format.s = "image/png")
  Declare IsLayer(Name.s)
  Declare DeleteLayer(Name.s)
  Declare EnableLayer(Name.s)
  Declare DisableLayer(Name.s)
  Declare SetLayerAlpha(Name.s, Alpha.d)
  Declare.d GetLayerAlpha(Name.s)
  Declare BindMapGadget(Gadget.i, TimerNB = 1)
  Declare SetCallBackLocation(*CallBackLocation)
  Declare SetCallBackMainPointer(CallBackMainPointer.i)  
  Declare SetCallBackDrawTile(*CallBackLocation)
  Declare SetCallBackMarker(*CallBackLocation)
  Declare SetCallBackLeftClic(*CallBackLocation)
  Declare SetCallBackModifyTileFile(*CallBackLocation)
  Declare.i MapGadget(Gadget.i, X.i, Y.i, Width.i, Height.i, TimerNB = 1)       ; Returns Gadget NB if #PB_Any is used for gadget
  Declare FreeMapGadget(Gadget.i)
  Declare.d GetLatitude()
  Declare.d GetLongitude()
  Declare.d GetMouseLatitude()
  Declare.d GetMouseLongitude()
  Declare.d GetAngle()
  Declare.i GetZoom()
  Declare.i GetMode()
  Declare SetMode(Mode.i = #MODE_DEFAULT)
  Declare SetMapScaleUnit(ScaleUnit=PBMAP::#SCALE_KM) 
  Declare SetLocation(latitude.d, longitude.d, Zoom = -1, mode.i = #PB_Absolute)
  Declare SetAngle(Angle.d, Mode = #PB_Absolute) 
  Declare SetZoom(Zoom.i, Mode.i = #PB_Relative)
  Declare SetZoomToArea(MinY.d, MaxY.d, MinX.d, MaxX.d)
  Declare SetZoomToTracks(*Tracks)
  Declare NominatimGeoLocationQuery(Address.s, *ReturnPosition = 0) ; Send back the position *ptr.GeographicCoordinates
  Declare.i LoadGpxFile(FileName.s)                                 ; 
  Declare.i SaveGpxFile(FileName.s, *Track)                         ; 
  Declare ClearTracks()
  Declare DeleteTrack(*Ptr)
  Declare DeleteSelectedTracks()
  Declare SetTrackColour(*Ptr, Colour.i)
  Declare.i AddMarker(Latitude.d, Longitude.d, Identifier.s = "", Legend.s = "", color.l=-1, CallBackPointer.i = -1)
  Declare ClearMarkers()
  Declare DeleteMarker(*Ptr)
  Declare DeleteSelectedMarkers()
  Declare Drawing()
  Declare FatalError(msg.s)
  Declare Error(msg.s)
  Declare Refresh()
  Declare.i ClearDiskCache()

EndDeclareModule

Module PBMap 
  
  EnableExplicit
  
  ;-*** Prototypes
  
  Prototype.i ProtoDrawTile(x.i, y.i, image.i, alpha.d = 1)
  Prototype.s ProtoModifyTileFile(Filename.s, OriginalURL.s)
  
  ;-*** Internal Structures
  
  Structure PixelCoordinates
    x.d
    y.d
  EndStructure
  
  Structure Coordinates
    x.d
    y.d
  EndStructure
  
  Structure Tile
    nImage.i
    key.s
    URL.s
    CacheFile.s
    GetImageThread.i
    Download.i
    Time.i
    Size.i
    Window.i                                       ; Parent Window
    Gadget.i 
  EndStructure
  
  Structure BoundingBox 
    NorthWest.GeographicCoordinates
    SouthEast.GeographicCoordinates 
    BottomRight.PixelCoordinates
    TopLeft.PixelCoordinates   
  EndStructure
  
  Structure DrawingParameters
    Canvas.i
    RadiusX.d                                     ; Canvas radius, or center in pixels
    RadiusY.d
    GeographicCoordinates.GeographicCoordinates   ; Real center in lat/lon
    TileCoordinates.Coordinates                   ; Center coordinates in tile.decimal
    Bounds.BoundingBox                            ; Drawing boundaries in lat/lon
    Width.d                                       ; Drawing width in degrees
    Height.d                                      ; Drawing height in degrees
    PBMapZoom.i
    DeltaX.i                                      ; Screen relative pixels tile shift
    DeltaY.i
    Dirty.i
    End.i
  EndStructure  
  
  Structure ImgMemCach
    nImage.i
    Size.i
    *Tile.Tile
    *TimeStackPtr
    Alpha.i
  EndStructure
  
  Structure ImgMemCachKey
    MapKey.s
  EndStructure
  
  Structure TileMemCach
    Map Images.ImgMemCach(4096)
    List ImagesTimeStack.ImgMemCachKey()           ; Usage of the tile (first = older)
  EndStructure
  
  ;-Options Structure
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
    ShowZoom.i
    ShowDebugInfos.i
    ShowScale.i
    ShowTrack.i
    ShowTrackKms.i
    ShowMarkers.i
    ShowPointer.i
    TimerInterval.i
    MaxMemCache.i                                  ; in MiB
    MaxThreads.i                                   ; Maximum simultaneous web loading threads
    MaxDownloadSlots.i                             ; Maximum simultaneous download slots
    TileLifetime.i
    Verbose.i                                      ; Maximum debug informations
    Warning.i                                      ; Warning requesters
    ShowMarkersNb.i
    ShowMarkersLegend.i
    ShowTrackSelection.i                           ; YA to show or not track selection
    ; Drawing stuff
    StrokeWidthTrackDefault.i
    ; Colours
    ColourFocus.i
    ColourSelected.i
    ColourTrackDefault.i
    ; HERE specific
    appid.s
    appcode.s
  EndStructure
  
  Structure Layer
    Order.i                                        ; Layer nb
    Name.s
    ServerURL.s                                    ; Web URL ex: http://tile.openstreetmap.org/  
    path.s
    LayerType.i                                    ; OSM : 0 ; Here : 1
    Enabled.i
    Alpha.d                                        ; 1 : opaque ; 0 : transparent
    format.s
    ; > HERE specific params
    APP_ID.s
    APP_CODE.s
    ressource.s
    param.s 
    id.s 
    scheme.s
    lg.s
    lg2.s
    ; <
    ; > GeoServer specific params
    ServerLayerName.s
    ; <
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
  
  ;- PBMap Structure
  Structure PBMap
    Window.i                                       ; Parent Window
    Gadget.i                                       ; Canvas Gadget Id 
    StandardFont.i                                 ; Font to use when writing on the map 
    UnderlineFont.i
    Timer.i                                        ; Redraw/update timer
    
    GeographicCoordinates.GeographicCoordinates    ; Latitude and Longitude from focus point
    Drawing.DrawingParameters                      ; Drawing parameters based on focus point
    
    CallBackLocation.i                             ; @Procedure(latitude.d, longitude.d)
    CallBackMainPointer.i                          ; @Procedure(X.i, Y.i) to DrawPointer (you must use VectorDrawing lib)
    CallBackMarker.i                               ; @Procedure (latitude.d, longitude.d) to know the marker position (YA)
    CallBackLeftClic.i                             ; @Procedure (latitude.d, longitude.d) to know the position on left click  (YA)
    CallBackDrawTile.ProtoDrawTile                 ; @Procedure (x.i, y.i, nImage.i) to customise tile drawing 
    CallBackModifyTileFile.ProtoModifyTileFile     ; @Procedure (Filename.s, Original URL) to customise image file => New Filename
    
    PixelCoordinates.PixelCoordinates              ; Actual focus point coords in pixels (global)
    MoveStartingPoint.PixelCoordinates             ; Start mouse position coords when dragging the map
    
    List LayersList.Layer()
    Map *Layers.Layer() 
    
    Angle.d
    ZoomMin.i                                      ; Min Zoom supported by server
    ZoomMax.i                                      ; Max Zoom supported by server
    Zoom.i                                         ; Current zoom
    TileSize.i                                     ; Tile size downloaded on the server ex : 256
    
    MemCache.TileMemCach                           ; Images in memory cache
    
    ThreadsNB.i                                    ; Current web threads nb
    
    Mode.i                                         ; User mode : 0 (default)->hand (moving map) and select markers, 1->hand, 2->select only (moving objects), 3->drawing (todo) 
    Redraw.i
    Dragging.i
    Dirty.i                                        ; To signal that drawing need a refresh
    
    MemoryCacheAccessMutex.i                       ; Memorycache access variable mutual exclusion    
    DownloadSlots.i                                ; Actual nb of used download slots
    
    List TracksList.Tracks()                       ; To display a GPX track
    List Markers.Marker()                          ; To diplay marker
    EditMarker.l
    
    ImgLoading.i                                   ; Image Loading Tile
    ImgNothing.i                                   ; Image Nothing Tile
    
    Options.option                                 ; Options
    
  EndStructure
  
  ;-*** Module's global variables  
  
  ;-Show debug infos 
  Global MyDebugLevel = 5
  
  Global NewMap PBMaps()
  Global *PBMap.PBMap
  Global slash.s
  
  CompilerSelect #PB_Compiler_OS
    CompilerCase #PB_OS_Windows
      Global slash = "\"
    CompilerDefault
      Global slash = "/"
  CompilerEndSelect  
  
  ;- *** GetText - Translation purpose
  
  ; TODO use this
  IncludeFile "gettext.pbi"
  
  ;-*** Misc tools
  
  Macro Min(a, b)
    (Bool((a) <= (b)) * (a) + Bool((b) < (a)) * (b))
  EndMacro
  
  Macro Max(a, b)
    (Bool((a) >= (b)) * (a) + Bool((b) > (a)) * (b))
  EndMacro
  
  ;-Error management
  
  ; Shows an error msg and terminates the program
  Procedure FatalError(msg.s)
    If *PBMap\Options\Warning
      MessageRequester("PBMap", msg, #PB_MessageRequester_Ok)
    EndIf
    End
  EndProcedure
  
  ; Shows an error msg
  Procedure Error(msg.s)
    If *PBMap\Options\Warning
      MessageRequester("PBMap", msg, #PB_MessageRequester_Ok)
    EndIf
  EndProcedure  
    
    ; Set the debug level allowing more or less debug infos
  Procedure SetDebugLevel(level.i)
    MyDebugLevel = level
  EndProcedure 
  
  ; Send debug infos to stdout (allowing mixed debug infos with curl or other libs)
  Procedure MyDebug(msg.s, DbgLevel = 0)
    If *PBMap\Options\Verbose And DbgLevel <= MyDebugLevel 
      PrintN(msg)
      ; Debug msg  
    EndIf
  EndProcedure
  
  ; Creates a full tree
  ; by Thomas (ts-soft) Schulz  
  ; http://www.purebasic.fr/english/viewtopic.php?f=12&t=58657&hilit=createdirectory&view=unread#unread
  CompilerSelect #PB_Compiler_OS
    CompilerCase #PB_OS_Windows
      #FILE_ATTRIBUTE_DEVICE              =     64 ; (0x40)
      #FILE_ATTRIBUTE_INTEGRITY_STREAM    =  32768 ; (0x8000)
      #FILE_ATTRIBUTE_NOT_CONTENT_INDEXED  =   8192; (0x2000)
      #FILE_ATTRIBUTE_NO_SCRUB_DATA        = 131072; (0x20000)
      #FILE_ATTRIBUTE_VIRTUAL              =  65536; (0x10000)
      #FILE_ATTRIBUTE_DONTSETFLAGS = ~(#FILE_ATTRIBUTE_DIRECTORY|
                                       #FILE_ATTRIBUTE_SPARSE_FILE|
                                       #FILE_ATTRIBUTE_OFFLINE|
                                       #FILE_ATTRIBUTE_NOT_CONTENT_INDEXED|
                                       #FILE_ATTRIBUTE_VIRTUAL|
                                       0)
      Macro SetFileAttributesEx(Name, Attribs)
        SetFileAttributes(Name, Attribs & #FILE_ATTRIBUTE_DONTSETFLAGS)
      EndMacro
    CompilerDefault
      Macro SetFileAttributesEx(Name, Attribs)
        SetFileAttributes(Name, Attribs)
      EndMacro
  CompilerEndSelect
  
  Procedure CreateDirectoryEx(DirectoryName.s, FileAttribute = #PB_Default)
    Protected i, c, tmp.s
    If Right(DirectoryName, 1) = slash
      DirectoryName = Left(DirectoryName, Len(DirectoryName) -1)
    EndIf
    c = CountString(DirectoryName, slash) + 1
    For i = 1 To c
      tmp + StringField(DirectoryName, i, slash)
      If FileSize(tmp) <> -2
        CreateDirectory(tmp)
      EndIf
      tmp + slash
    Next
    If FileAttribute <> #PB_Default
      SetFileAttributesEx(DirectoryName, FileAttribute)
    EndIf
    If FileSize(DirectoryName) = -2
      ProcedureReturn #True
    EndIf
  EndProcedure
  
  Procedure TechnicalImagesCreation()
    ; "Loading" image
    Protected LoadingText$ = "Loading"
    Protected NothingText$ = "Nothing"
    *PBMap\ImgLoading = CreateImage(#PB_Any, 256, 256) 
    If *PBMap\ImgLoading
      StartVectorDrawing(ImageVectorOutput(*PBMap\Imgloading)) 
      BeginVectorLayer()
      VectorSourceColor(RGBA(255, 255, 255, 128))
      AddPathBox(0, 0, 256, 256)
      FillPath()
      MovePathCursor(0, 0)
      VectorFont(FontID(*PBMap\StandardFont), 256 / 20)
      VectorSourceColor(RGBA(150, 150, 150, 255))
      MovePathCursor(0 + (256 - VectorTextWidth(LoadingText$)) / 2, 0 + (256 - VectorTextHeight(LoadingText$)) / 2)
      DrawVectorText(LoadingText$)
      EndVectorLayer()
      StopVectorDrawing() 
    EndIf
    ; "Nothing" tile
    *PBMap\ImgNothing = CreateImage(#PB_Any, 256, 256) 
    If *PBMap\ImgNothing
      StartVectorDrawing(ImageVectorOutput(*PBMap\ImgNothing)) 
      ; BeginVectorLayer()
      VectorSourceColor(RGBA(220, 230, 255, 255))
      AddPathBox(0, 0, 256, 256)
      FillPath()
      ; MovePathCursor(0, 0)
      ; VectorFont(FontID(*PBMap\StandardFont), 256 / 20)
      ; VectorSourceColor(RGBA(150, 150, 150, 255))
      ; MovePathCursor(0 + (256 - VectorTextWidth(NothingText$)) / 2, 0 + (256 - VectorTextHeight(NothingText$)) / 2)
      ; DrawVectorText(NothingText$)
      ; EndVectorLayer()
      StopVectorDrawing() 
    EndIf
  EndProcedure  
  
  Procedure.d Distance(x1.d, y1.d, x2.d, y2.d)
    Protected Result.d
    Result = Sqr( (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))
    ProcedureReturn Result
  EndProcedure
  
  ; *** Converts coords to tile.decimal
  ; Warning, structures used in parameters are not tested
  Procedure LatLon2TileXY(*Location.GeographicCoordinates, *Coords.Coordinates, Zoom)
    Protected n.d = Pow(2.0, Zoom)
    Protected LatRad.d = Radian(*Location\Latitude)
    *Coords\x = n * (Mod( *Location\Longitude + 180.0, 360) / 360.0 )
    *Coords\y = n * ( 1.0 - Log(Tan(LatRad) + (1.0/Cos(LatRad))) / #PI ) / 2.0
    MyDebug("Latitude : " + StrD(*Location\Latitude) + " ; Longitude : " + StrD(*Location\Longitude), 5)
    MyDebug("Coords X : " + Str(*Coords\x) + " ; Y : " + Str(*Coords\y), 5)
  EndProcedure
  
  ; *** Converts tile.decimal to coords
  ; Warning, structures used in parameters are not tested
  Procedure TileXY2LatLon(*Coords.Coordinates, *Location.GeographicCoordinates, Zoom)
    Protected n.d = Pow(2.0, Zoom)
    ; Ensures the longitude to be in the range [-180; 180[
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
    Protected n.d = *PBMap\TileSize * Pow(2.0, Zoom)
    ; Ensures the longitude to be in the range [-180; 180[
    *Location\Longitude  = Mod(Mod(*Coords\x / n * 360.0, 360.0) + 360.0, 360.0) - 180
    *Location\Latitude = Degree(ATan(SinH(#PI * (1.0 - 2.0 * *Coords\y / n))))
    If *Location\Latitude <= -89 
      *Location\Latitude = -89 
    EndIf
    If *Location\Latitude >= 89
      *Location\Latitude = 89 
    EndIf
  EndProcedure
  
  ; Ensures the longitude to be in the range [-180; 180[
  Procedure.d ClipLongitude(Longitude.d)
    ProcedureReturn Mod(Mod(Longitude + 180, 360.0) + 360.0, 360.0) - 180
  EndProcedure
  
  ; Lat Lon coordinates 2 pixel absolute [0 to 2^Zoom * TileSize [
  Procedure LatLon2Pixel(*Location.GeographicCoordinates, *Pixel.PixelCoordinates, Zoom) 
    Protected tilemax = Pow(2.0, Zoom) * *PBMap\TileSize 
    Protected LatRad.d = Radian(*Location\Latitude)
    *Pixel\x = tilemax * (Mod( *Location\Longitude + 180.0, 360) / 360.0 )
    *Pixel\y = tilemax * ( 1.0 - Log(Tan(LatRad) + (1.0/Cos(LatRad))) / #PI ) / 2.0
  EndProcedure   
  
  ; Lat Lon coordinates 2 pixel relative to the center of view
  Procedure LatLon2PixelRel(*Location.GeographicCoordinates, *Pixel.PixelCoordinates, Zoom) 
    Protected tilemax = Pow(2.0, Zoom) * *PBMap\TileSize 
    Protected cx.d  = *PBMap\Drawing\RadiusX
    Protected dpx.d = *PBMap\PixelCoordinates\x
    Protected LatRad.d = Radian(*Location\Latitude)
    Protected px.d = tilemax * (Mod( *Location\Longitude + 180.0, 360) / 360.0 )
    Protected py.d = tilemax * ( 1.0 - Log(Tan(LatRad) + (1.0/Cos(LatRad))) / #PI ) / 2.0    
    ; check the x boundaries of the map to adjust the position (coz of the longitude wrapping)
    If dpx - px >= tilemax / 2
      ; Debug "c1"
      *Pixel\x = cx + (px - dpx + tilemax)
    ElseIf px - dpx > tilemax / 2
      ; Debug "c2"
      *Pixel\x = cx + (px - dpx - tilemax)
    ElseIf px - dpx < 0
      ; Debug "c3"
      *Pixel\x = cx - (dpx - px)
    Else
      ; Debug "c0"
      *Pixel\x = cx + (px - dpx) 
    EndIf
    *Pixel\y = *PBMap\Drawing\RadiusY + (py - *PBMap\PixelCoordinates\y) 
  EndProcedure
  
  Procedure.d Pixel2Lon(x)
    Protected NewX.d = (*PBMap\PixelCoordinates\x - *PBMap\Drawing\RadiusX + x) / *PBMap\TileSize
    Protected n.d = Pow(2.0, *PBMap\Zoom)
    ; double mod is to ensure the longitude to be in the range [-180; 180[
    ProcedureReturn Mod(Mod(NewX / n * 360.0, 360.0) + 360.0, 360.0) - 180
  EndProcedure
  
  Procedure.d Pixel2Lat(y)
    Protected NewY.d = (*PBMap\PixelCoordinates\y - *PBMap\Drawing\RadiusY + y) / *PBMap\TileSize
    Protected n.d = Pow(2.0, *PBMap\Zoom)
    ProcedureReturn Degree(ATan(SinH(#PI * (1.0 - 2.0 * NewY / n))))
  EndProcedure
  
  ; HaversineAlgorithm 
  ; http://andrew.hedges.name/experiments/haversine/
  Procedure.d HaversineInKM(*posA.GeographicCoordinates, *posB.GeographicCoordinates)
    Protected eQuatorialEarthRadius.d = 6378.1370; 6372.795477598; 
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
    x2 = (*PBMap\GeographicCoordinates\Longitude+180)*(mapWidth/360)
    ; convert from degrees To radians
    latRad = *PBMap\GeographicCoordinates\Latitude*#PI/180; 
    mercN = Log(Tan((#PI/4)+(latRad/2)))        
    y2     = (mapHeight/2)-(mapWidth*mercN/(2*#PI)); 
    *Pixel\x=*PBMap\Drawing\RadiusX  - (x2-x1)
    *Pixel\y=*PBMap\Drawing\RadiusY - (y2-y1)
  EndProcedure
  
  Procedure IsInDrawingPixelBoundaries(*Drawing.DrawingParameters, *Position.GeographicCoordinates)
    Protected Pixel.PixelCoordinates
    LatLon2PixelRel(*Position, @Pixel, *PBMap\Zoom)
    If Pixel\x >= 0 And Pixel\y >= 0 And Pixel\x < *Drawing\RadiusX * 2 And Pixel\y < *Drawing\RadiusY * 2
      ProcedureReturn #True
    Else
      ProcedureReturn #False
    EndIf
  EndProcedure
  
  Procedure.i IsInDrawingBoundaries(*Drawing.DrawingParameters, *Position.GeographicCoordinates)
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
  
  ; TODO : best cleaning of the string from bad behaviour
  Procedure.s StringCheck(String.s)
    ProcedureReturn Trim(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(RemoveString(String, Chr(0)), Chr(32)), Chr(39)), Chr(33)), Chr(34)), "@"), "/"), "\"), "$"), "%"))
  EndProcedure
  
  Procedure.i ColourString2Value(Value.s)
    ; TODO : better string check
    Protected Col.s = RemoveString(Value, " ")
    If Left(Col, 1) = "$"
      Protected r.i, g.i, b.i, a.i = 255
      Select Len(Col)
        Case 4 ; RGB  (eg : "$9BC"
          r = Val("$"+Mid(Col, 2, 1)) : g = Val("$"+Mid(Col, 3, 1)) : b = Val("$"+Mid(Col, 4, 1))
        Case 5 ; RGBA (eg : "$9BC5")
          r = Val("$"+Mid(Col, 2, 1)) : g = Val("$"+Mid(Col, 3, 1)) : b = Val("$"+Mid(Col, 4, 1)) : a = Val("$"+Mid(Col, 5, 1))
        Case 7 ; RRGGBB (eg : "$95B4C2")
          r = Val("$"+Mid(Col, 2, 2)) : g = Val("$"+Mid(Col, 4, 2)) : b = Val("$"+Mid(Col, 6, 2))
        Case 9 ; RRGGBBAA (eg : "$95B4C249")
          r = Val("$"+Mid(Col, 2, 2)) : g = Val("$"+Mid(Col, 4, 2)) : b = Val("$"+Mid(Col, 6, 2)) : a = Val("$"+Mid(Col, 8, 2))
      EndSelect
      ProcedureReturn RGBA(r, g, b, a)
    Else
      ProcedureReturn Val(Value)
    EndIf
  EndProcedure 
  
  Procedure.s Value2ColourString(Value.i)
    ProcedureReturn "$" + StrU(Red(Value), #PB_Byte) + StrU(Green(Value), #PB_Byte) + StrU(Blue(Value), #PB_Byte)
  EndProcedure
  
  ;-*** Options
  
  Procedure SetOptions()
    With *PBMap\Options
      If \Proxy
        HTTPProxy(*PBMap\Options\ProxyURL + ":" + *PBMap\Options\ProxyPort, *PBMap\Options\ProxyUser, *PBMap\Options\ProxyPassword)
      EndIf
      If \Verbose
        OpenConsole()
      EndIf
      CreateDirectoryEx(\HDDCachePath)
      If \DefaultOSMServer <> "" And IsLayer("OSM") = #False ; First time creation of the basis OSM layer
        AddOSMServerLayer("OSM", 1, \DefaultOSMServer)
      EndIf
    EndWith
  EndProcedure
  
  Macro SelBool(Name)
    Select UCase(Value)
      Case "0", "FALSE", "DISABLE"
        *PBMap\Options\Name = #False
      Default
        *PBMap\Options\Name = #True
    EndSelect
  EndMacro
  
  Procedure SetOption(Option.s, Value.s)
    Option = StringCheck(Option)
    Select LCase(Option)
      Case "proxy"
        SelBool(Proxy)
      Case "proxyurl"
        *PBMap\Options\ProxyURL = Value
      Case "proxyport"        
        *PBMap\Options\ProxyPort = Value
      Case "proxyuser"        
        *PBMap\Options\ProxyUser = Value
      Case "appid"        
        *PBMap\Options\appid = Value
      Case "appcode"        
        *PBMap\Options\appcode = Value
      Case "tilescachepath"
        *PBMap\Options\HDDCachePath = Value
      Case "maxmemcache"
        *PBMap\Options\MaxMemCache = Val(Value)
      Case "maxthreads"
        *PBMap\Options\MaxThreads = Val(Value)
      Case "maxdownloadslots"
        *PBMap\Options\MaxDownloadSlots = Val(Value)
      Case "tilelifetime"
        *PBMap\Options\TileLifetime =  Val(Value)
      Case "verbose"
        SelBool(Verbose)
      Case "warning"
        SelBool(Warning)
      Case "wheelmouserelative"
        SelBool(WheelMouseRelative)
      Case "showdegrees"
        SelBool(ShowDegrees)
      Case "showzoom"
        SelBool(ShowZoom)
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
      Case "showtrackselection"
        SelBool(ShowTrackSelection)
      Case "showmarkersnb"
        SelBool(ShowMarkersNb)      
      Case "showmarkerslegend"
        SelBool(ShowMarkersLegend)      
      Case "showtrackkms"
        SelBool(ShowTrackKms)
      Case "strokewidthtrackdefault"
        SelBool(StrokeWidthTrackDefault)
      Case "colourfocus"
        *PBMap\Options\ColourFocus = ColourString2Value(Value)
      Case "colourselected"
        *PBMap\Options\ColourSelected = ColourString2Value(Value)
      Case "colourtrackdefault"
        *PBMap\Options\ColourTrackDefault = ColourString2Value(Value)
    EndSelect
    SetOptions()
  EndProcedure
  
  Procedure.s GetBoolString(Value.i)
    Select Value
      Case #False
        ProcedureReturn "0"
      Default
        ProcedureReturn "1"
    EndSelect
  EndProcedure
  
  Procedure.s GetOption(Option.s)
    Option = StringCheck(Option)
    With *PBMap\Options
      Select LCase(Option)
        Case "proxy"
          ProcedureReturn GetBoolString(\Proxy)
        Case "proxyurl"
          ProcedureReturn \ProxyURL
        Case "proxyport"        
          ProcedureReturn \ProxyPort
        Case "proxyuser"        
          ProcedureReturn \ProxyUser
        Case "appid"        
          ProcedureReturn \appid
        Case "appcode"        
          ProcedureReturn \appcode
        Case "tilescachepath"
          ProcedureReturn \HDDCachePath
        Case "maxmemcache"
          ProcedureReturn StrU(\MaxMemCache)
        Case "maxthreads"
          ProcedureReturn StrU(\MaxThreads)
        Case "maxdownloadslots"
          ProcedureReturn StrU(\MaxDownloadSlots)
        Case "tilelifetime"
          ProcedureReturn StrU(\TileLifetime)  
        Case "verbose"
          ProcedureReturn GetBoolString(\Verbose)
        Case "warning"
          ProcedureReturn GetBoolString(\Warning)
        Case "wheelmouserelative"
          ProcedureReturn GetBoolString(\WheelMouseRelative)
        Case "showdegrees"
          ProcedureReturn GetBoolString(\ShowDegrees)
        Case "showdebuginfos"
          ProcedureReturn GetBoolString(\ShowDebugInfos)
        Case "showscale"
          ProcedureReturn GetBoolString(\ShowScale)
        Case "showzoom"
          ProcedureReturn GetBoolString(\ShowZoom)
        Case "showmarkers"
          ProcedureReturn GetBoolString(\ShowMarkers)
        Case "showpointer"
          ProcedureReturn GetBoolString(\ShowPointer)
        Case "showtrack"
          ProcedureReturn GetBoolString(\ShowTrack)
        Case "showtrackselection"
          ProcedureReturn GetBoolString(\ShowTrackSelection)
        Case "showmarkersnb"
          ProcedureReturn GetBoolString(\ShowMarkersNb)      
        Case "showmarkerslegend"
          ProcedureReturn GetBoolString(\ShowMarkersLegend)      
        Case "showtrackkms"
          ProcedureReturn GetBoolString(\ShowTrackKms)
        Case "strokewidthtrackdefault"
          ProcedureReturn GetBoolString(\StrokeWidthTrackDefault)
        Case "colourfocus"
          ProcedureReturn Value2ColourString(\ColourFocus)
        Case "colourselected"
          ProcedureReturn Value2ColourString(\ColourSelected)
        Case "colourtrackdefault"
          ProcedureReturn Value2ColourString(\ColourTrackDefault)
      EndSelect
    EndWith
  EndProcedure
    
  ; By default, save options in the user's home directory
  Procedure SaveOptions(PreferencesFile.s = "PBMap.prefs")
    If PreferencesFile = "PBMap.prefs"
      CreatePreferences(GetHomeDirectory() + "PBMap.prefs")      
    Else
      CreatePreferences(PreferencesFile)     
    EndIf
    With *PBMap\Options
      PreferenceGroup("PROXY")
      WritePreferenceInteger("Proxy", \Proxy)
      WritePreferenceString("ProxyURL", \ProxyURL)
      WritePreferenceString("ProxyPort", \ProxyPort)
      WritePreferenceString("ProxyUser", \ProxyUser)
      PreferenceGroup("HERE")
      WritePreferenceString("APP_ID", \appid)
      WritePreferenceString("APP_CODE", \appcode)
      PreferenceGroup("URL")
      WritePreferenceString("DefaultOSMServer", \DefaultOSMServer)
      PreferenceGroup("PATHS")
      WritePreferenceString("TilesCachePath", \HDDCachePath)
      PreferenceGroup("OPTIONS")
      WritePreferenceInteger("WheelMouseRelative", \WheelMouseRelative)
      WritePreferenceInteger("MaxMemCache", \MaxMemCache)
      WritePreferenceInteger("MaxThreads", \MaxThreads)
      WritePreferenceInteger("MaxDownloadSlots", \MaxDownloadSlots)
      WritePreferenceInteger("TileLifetime", \TileLifetime)  
      WritePreferenceInteger("Verbose", \Verbose)
      WritePreferenceInteger("Warning", \Warning)
      WritePreferenceInteger("ShowDegrees", \ShowDegrees)
      WritePreferenceInteger("ShowDebugInfos", \ShowDebugInfos)
      WritePreferenceInteger("ShowScale", \ShowScale)
      WritePreferenceInteger("ShowZoom", \ShowZoom)
      WritePreferenceInteger("ShowMarkers", \ShowMarkers)
      WritePreferenceInteger("ShowPointer", \ShowPointer)
      WritePreferenceInteger("ShowTrack", \ShowTrack)
      WritePreferenceInteger("ShowTrackSelection", \ShowTrackSelection)
      WritePreferenceInteger("ShowTrackKms", \ShowTrackKms)
      WritePreferenceInteger("ShowMarkersNb", \ShowMarkersNb)
      WritePreferenceInteger("ShowMarkersLegend", \ShowMarkersLegend)
      PreferenceGroup("DRAWING")  
      WritePreferenceInteger("StrokeWidthTrackDefault", \StrokeWidthTrackDefault)
      ; Colours; 
      WritePreferenceInteger("ColourFocus", \ColourFocus)
      WritePreferenceInteger("ColourSelected", \ColourSelected)
      WritePreferenceInteger("ColourTrackDefault", \ColourTrackDefault)
      ClosePreferences()
    EndWith
  EndProcedure
  
  Procedure LoadOptions(MapGadget.i, PreferencesFile.s = "PBMap.prefs")
    Protected *PBMap.PBMap = PBMaps(Str(MapGadget))
    If PreferencesFile = "PBMap.prefs"
      OpenPreferences(GetHomeDirectory() + "PBMap.prefs")      
    Else
      OpenPreferences(PreferencesFile)     
    EndIf
    ; Use this to create and customize your preferences file for the first time
    ; CreatePreferences(GetHomeDirectory() + "PBMap.prefs")
    ; ; Or this to modify
    ; ; OpenPreferences(GetHomeDirectory() + "PBMap.prefs")
    ; ; Or this 
    ; ; RunProgram("notepad.exe",  GetHomeDirectory() + "PBMap.prefs", GetHomeDirectory())
    ; PreferenceGroup("PROXY")
    ; WritePreferenceInteger("Proxy", #True)
    ; WritePreferenceString("ProxyURL", "myproxy.fr")
    ; WritePreferenceString("ProxyPort", "myproxyport")
    ; WritePreferenceString("ProxyUser", "myproxyname")       
    ; WritePreferenceString("ProxyPass", "myproxypass") ; TODO !Warning! !not encoded!
    ; PreferenceGroup("HERE")
    ; WritePreferenceString("APP_ID", "myhereid")       ; TODO !Warning! !not encoded!
    ; WritePreferenceString("APP_CODE", "myherecode")   ; TODO !Warning! !not encoded!
    ; ClosePreferences()
    With *PBMap\Options
      PreferenceGroup("PROXY")       
      \Proxy              = ReadPreferenceInteger("Proxy", #False)
      If \Proxy
        \ProxyURL         = ReadPreferenceString("ProxyURL", "")  ; = InputRequester("ProxyServer", "Do you use a Proxy Server? Then enter the full url:", "")
        \ProxyPort        = ReadPreferenceString("ProxyPort", "") ; = InputRequester("ProxyPort", "Do you use a specific port? Then enter it", "")
        \ProxyUser        = ReadPreferenceString("ProxyUser", "") ; = InputRequester("ProxyUser", "Do you use a user name? Then enter it", "")
        \ProxyPassword    = ReadPreferenceString("ProxyPass", "") ; = InputRequester("ProxyPass", "Do you use a password ? Then enter it", "") ; TODO
      EndIf
      PreferenceGroup("HERE")  
      \appid            = ReadPreferenceString("APP_ID", "")    ; = InputRequester("Here App ID", "Do you use HERE ? Enter app ID", "") ; TODO
      \appcode          = ReadPreferenceString("APP_CODE", "")  ; = InputRequester("Here App Code", "Do you use HERE ? Enter app Code", "") ; TODO
      PreferenceGroup("URL")
      \DefaultOSMServer   = ReadPreferenceString("DefaultOSMServer", "http://tile.openstreetmap.org/")
      
      PreferenceGroup("PATHS")
      \HDDCachePath       = ReadPreferenceString("TilesCachePath", GetTemporaryDirectory() + "PBMap" + slash)
      PreferenceGroup("OPTIONS")   
      \WheelMouseRelative = ReadPreferenceInteger("WheelMouseRelative", #True)
      \MaxMemCache        = ReadPreferenceInteger("MaxMemCache", 20480) ; 20 MiB, about 80 tiles in memory
      \MaxThreads         = ReadPreferenceInteger("MaxThreads", 40)
      \MaxDownloadSlots   = ReadPreferenceInteger("MaxDownloadSlots", 2)
      \TileLifetime       = ReadPreferenceInteger("TileLifetime", 1209600) ; about 2 weeks ;-1 = unlimited
      \Verbose            = ReadPreferenceInteger("Verbose", #False)
      \Warning            = ReadPreferenceInteger("Warning", #False)
      \ShowDegrees        = ReadPreferenceInteger("ShowDegrees", #False)
      \ShowDebugInfos     = ReadPreferenceInteger("ShowDebugInfos", #False)
      \ShowScale          = ReadPreferenceInteger("ShowScale", #False)
      \ShowZoom           = ReadPreferenceInteger("ShowZoom", #True)
      \ShowMarkers        = ReadPreferenceInteger("ShowMarkers", #True)
      \ShowPointer        = ReadPreferenceInteger("ShowPointer", #True)
      \ShowTrack          = ReadPreferenceInteger("ShowTrack", #True)
      \ShowTrackSelection = ReadPreferenceInteger("ShowTrackSelection", #False)
      \ShowTrackKms       = ReadPreferenceInteger("ShowTrackKms", #False)
      \ShowMarkersNb      = ReadPreferenceInteger("ShowMarkersNb", #True)
      \ShowMarkersLegend  = ReadPreferenceInteger("ShowMarkersLegend", #False)
      PreferenceGroup("DRAWING")   
      \StrokeWidthTrackDefault = ReadPreferenceInteger("StrokeWidthTrackDefault", 10)
      PreferenceGroup("COLOURS")
      \ColourFocus        = ReadPreferenceInteger("ColourFocus", RGBA(255, 255, 0, 255))
      \ColourSelected     = ReadPreferenceInteger("ColourSelected", RGBA(225, 225, 0, 255))
      \ColourTrackDefault = ReadPreferenceInteger("ColourTrackDefault", RGBA(0, 255, 0, 150))
      \TimerInterval      = 12
      ClosePreferences()         
    EndWith
    SetOptions()
  EndProcedure
  
  ;-*** Layers
  ; Add a layer to a list (to get things ordered) and to a map (to access things easily)
  Procedure.i AddLayer(Name.s, Order.i, Alpha.d)
    Protected *Ptr = 0
    *Ptr = AddMapElement(*PBMap\Layers(), Name)
    If *Ptr
      *PBMap\Layers() = AddElement(*PBMap\LayersList()) ; This map element is a ptr to a linked list element
      If *PBMap\Layers()
        *PBMap\LayersList()\Name  = Name
        *PBMap\LayersList()\Order = Order
        *PBMap\LayersList()\Alpha = Alpha
        SortStructuredList(*PBMap\LayersList(), #PB_Sort_Ascending, OffsetOf(Layer\Order), TypeOf(Layer\Order))
        ProcedureReturn *PBMap\Layers()
      Else
        *Ptr = 0
      EndIf
    EndIf
    ProcedureReturn *Ptr
  EndProcedure
  
  ; "OpenStreetMap" layer
  Procedure.i AddOSMServerLayer(LayerName.s, Order.i, ServerURL.s = "http://tile.openstreetmap.org/")
    Protected *Ptr.Layer = AddLayer(LayerName, Order, 1)
    If *Ptr
      *Ptr\ServerURL = ServerURL
      *Ptr\LayerType = 0 ; OSM
      *Ptr\Enabled = #True
      *PBMap\Redraw = #True
      ProcedureReturn *Ptr
    Else
      ProcedureReturn #False
    EndIf
  EndProcedure
  
  ; "Here" layer
  ; see there for parameters : https://developer.here.com/rest-apis/documentation/enterprise-map-tile/topics/resource-base-maptile.html
  ; you could use base.maps.api.here.com or aerial.maps.api.here.com or traffic.maps.api.here.com or pano.maps.api.here.com. 
  ; use *.cit.map.api.com For Customer Integration Testing (see https://developer.here.com/rest-apis/documentation/enterprise-Map-tile/common/request-cit-environment-rest.html)
  Procedure.i AddHereServerLayer(LayerName.s, Order.i, APP_ID.s = "", APP_CODE.s = "", ServerURL.s = "aerial.maps.api.here.com", path.s = "/maptile/2.1/", ressource.s = "maptile", id.s = "newest", scheme.s = "satellite.day", format.s = "jpg", lg.s = "eng", lg2.s = "eng", param.s = "")
    Protected *Ptr.Layer = AddLayer(LayerName, Order, 1)
    If *Ptr
      With *Ptr ; *PBMap\Layers()
        \ServerURL = ServerURL
        \path = path
        \ressource = ressource
        \LayerType = 1 ; HERE
        \Enabled = #True
        If APP_ID = ""
          APP_ID = *PBMap\Options\appid
        EndIf
        If APP_CODE = ""
          APP_CODE = *PBMap\Options\appcode
        EndIf
        \APP_CODE = APP_CODE
        \APP_ID = APP_ID
        \format = format
        \id = id
        \lg = lg
        \lg2 = lg2
        \param = param
        \scheme = scheme
      EndWith     
      *PBMap\Redraw = #True
      ProcedureReturn *Ptr
    Else
      ProcedureReturn #False
    EndIf
  EndProcedure
  
  ; GeoServer / geowebcache - google maps service
  ; template 'http://localhost:8080/geowebcache/service/gmaps?layers=layer-name&zoom={Z}&x={X}&y={Y}&format=image/png'
  Procedure.i AddGeoServerLayer(LayerName.s, Order.i, ServerLayerName.s, ServerURL.s = "http://localhost:8080/", path.s = "geowebcache/service/gmaps", format.s = "image/png")
    Protected *Ptr.Layer = AddLayer(LayerName, Order, 1)
    If *Ptr
      With *Ptr ; *PBMap\Layers()    
        \ServerURL = ServerURL
        \path = path
        \LayerType = 2 ; GeoServer
        \format = format
        \Enabled = #True
        \ServerLayerName = ServerLayerName
      EndWith
      *PBMap\Redraw = #True
      ProcedureReturn *Ptr
    Else
      ProcedureReturn #False
    EndIf
  EndProcedure
  
  Procedure.i IsLayer(Name.s)
    ProcedureReturn FindMapElement(*PBMap\Layers(), Name)
  EndProcedure
  
  Procedure DeleteLayer(Name.s)
    FindMapElement(*PBMap\Layers(), Name)
    Protected *Ptr = *PBMap\Layers()
    ; Free the list element
    ChangeCurrentElement(*PBMap\LayersList(), *Ptr)
    DeleteElement(*PBMap\LayersList())
    ; Free the map element
    DeleteMapElement(*PBMap\Layers())
    *PBMap\Redraw = #True
  EndProcedure
  
  Procedure EnableLayer(Name.s)
    *PBMap\Layers(Name)\Enabled = #True
    *PBMap\Redraw = #True
  EndProcedure
  
  Procedure DisableLayer(Name.s)
    *PBMap\Layers(Name)\Enabled = #False
    *PBMap\Redraw = #True
  EndProcedure
  
  Procedure SetLayerAlpha(Name.s, Alpha.d)
    *PBMap\Layers(Name)\Alpha = Alpha
    *PBMap\Redraw = #True
  EndProcedure
  
  Procedure.d GetLayerAlpha(Name.s)
    ProcedureReturn *PBMap\Layers(Name)\Alpha
  EndProcedure
  
  ;-***
  ; If cache size exceeds limit, try to delete the oldest tiles used (first in the time stack)
  Procedure MemoryCacheManagement()
    LockMutex(*PBMap\MemoryCacheAccessMutex) ; Prevents thread to start or finish
    Protected CacheSize = MapSize(*PBMap\MemCache\Images()) * Pow(*PBMap\TileSize, 2) * 4 ; Size of a tile = TileSize * TileSize * 4 bytes (RGBA) 
    Protected CacheLimit = *PBMap\Options\MaxMemCache * 1024
    MyDebug("Cache size : " + Str(CacheSize/1024) + " / CacheLimit : " + Str(CacheLimit/1024), 5)
    If CacheSize > CacheLimit    
      MyDebug(" Cache full. Trying cache cleaning", 5)
      ResetList(*PBMap\MemCache\ImagesTimeStack())
      ; Try to free half the cache memory (one pass)
      While NextElement(*PBMap\MemCache\ImagesTimeStack()) And CacheSize > (CacheLimit / 2) ; /2 = half
        Protected CacheMapKey.s = *PBMap\MemCache\ImagesTimeStack()\MapKey
        ; Is the loading over
        If *PBMap\MemCache\Images(CacheMapKey)\Tile <= 0 ;TODO Should not verify this var directly
          MyDebug("  Delete " + CacheMapKey, 5)
          If *PBMap\MemCache\Images(CacheMapKey)\nImage;IsImage(*PBMap\MemCache\Images(CacheMapKey)\nImage)
            FreeImage(*PBMap\MemCache\Images(CacheMapKey)\nImage)
            MyDebug("   and free image nb " + Str(*PBMap\MemCache\Images(CacheMapKey)\nImage), 5)
            *PBMap\MemCache\Images(CacheMapKey)\nImage = 0
          EndIf
          DeleteMapElement(*PBMap\MemCache\Images(), CacheMapKey)
          DeleteElement(*PBMap\MemCache\ImagesTimeStack(), 1)
          ;           ElseIf *PBMap\MemCache\Images(CacheMapKey)\Tile = 0 
          ;             MyDebug("  Delete " + CacheMapKey, 5)
          ;             DeleteMapElement(*PBMap\MemCache\Images(), CacheMapKey)
          ;             DeleteElement(*PBMap\MemCache\ImagesTimeStack(), 1)
          ;           ElseIf *PBMap\MemCache\Images(CacheMapKey)\Tile > 0
          ;             ; If the thread is running, try to abort the download
          ;             If *PBMap\MemCache\Images(CacheMapKey)\Tile\Download
          ;               AbortHTTP(*PBMap\MemCache\Images(CacheMapKey)\Tile\Download) ; Could lead to error
          ;             EndIf
        EndIf
        CacheSize = MapSize(*PBMap\MemCache\Images()) * Pow(*PBMap\TileSize, 2) * 4 ; Size of a tile = TileSize * TileSize * 4 bytes (RGBA) 
      Wend
      MyDebug("  New cache size : " + Str(CacheSize/1024) + " / CacheLimit : " + Str(CacheLimit/1024), 5)      
      If CacheSize > CacheLimit
        MyDebug("  Cache cleaning unsuccessfull, can't add new tiles.", 5)
      EndIf
    EndIf
    UnlockMutex(*PBMap\MemoryCacheAccessMutex)
  EndProcedure
  
  Procedure.i GetTileFromHDD(CacheFile.s)
    Protected nImage.i, LifeTime.i, MaxLifeTime.i
      ; Everything is OK, loads the file
      nImage = LoadImage(#PB_Any, CacheFile)
      If nImage
        MyDebug(" Success loading " + CacheFile + " as nImage " + Str(nImage), 3)
        ProcedureReturn nImage  
      Else
        MyDebug(" Failed loading " + CacheFile + " as nImage " + Str(nImage) + " -> not an image !", 3)
        If DeleteFile(CacheFile)
          MyDebug("  Deleting faulty image file  " + CacheFile, 3)
        Else
          MyDebug("  Can't delete faulty image file  " + CacheFile, 3)
        EndIf
      EndIf
    ProcedureReturn #False
  EndProcedure
  
  ; **** OLD IMPORTANT NOTICE (please not remove)
  ; This original catchimage/saveimage method is a double operation (uncompress/recompress PNG)
  ; and is modifying the original PNG image which could lead to PNG error (Idle has spent hours debunking the 1 bit PNG bug)
  ; Protected *Buffer
  ; Protected nImage.i = -1
  ; Protected timg
  ; *Buffer = ReceiveHTTPMemory(TileURL)  ; TODO to thread by using #PB_HTTP_Asynchronous
  ; If *Buffer
  ; nImage = CatchImage(#PB_Any, *Buffer, MemorySize(*Buffer))
  ; If IsImage(nImage)
  ; If SaveImage(nImage, CacheFile, #PB_ImagePlugin_PNG, 0, 32) ; The 32 is needed !!!!
  ; MyDebug("Loaded from web " + TileURL + " as CacheFile " + CacheFile, 3)
  ; Else
  ; MyDebug("Loaded from web " + TileURL + " but cannot save to CacheFile " + CacheFile, 3)
  ; EndIf
  ; FreeMemory(*Buffer)
  ; Else
  ; MyDebug("Can't catch image loaded from web " + TileURL, 3)
  ; nImage = -1
  ; EndIf
  ; Else
  ; MyDebug(" Problem loading from web " + TileURL, 3)
  ; EndIf
  ; ****
  
  ;-*** These are threaded
  
  Threaded Progress = 0, Quit = #False
  
  Procedure GetImageThread(*Tile.Tile)    
    ;LockMutex(*PBMap\MemoryCacheAccessMutex)
    MyDebug("Thread nb " + Str(*Tile\GetImageThread) + " " + *Tile\key + " starting for image " + *Tile\CacheFile, 5)
    ; If MemoryCache is currently being cleaned, abort
;     If *PBMap\MemoryCacheAccessNB = -1
;       MyDebug(" Thread nb " + Str(*Tile\GetImageThread) + " " + *Tile\key + "  for image " + *Tile\CacheFile + " canceled because of cleaning.", 5)
;       *Tile\Size = 0 ; \Size = 0 signals that the download has failed
;       PostEvent(#PB_Event_Gadget, *PBMap\Window, *PBMap\Gadget, #PB_MAP_TILE_CLEANUP, *Tile) ; To free memory outside the thread
;       UnlockMutex(*PBMap\MemoryCacheAccessMutex)
;       ProcedureReturn
;     EndIf
    ; We're accessing MemoryCache
    ;UnlockMutex(*PBMap\MemoryCacheAccessMutex)
    *Tile\Size = 0
    *Tile\Download = ReceiveHTTPFile(*Tile\URL, *Tile\CacheFile, #PB_HTTP_Asynchronous, #USERAGENT)
    If *Tile\Download
      Repeat
        Progress = HTTPProgress(*Tile\Download)
        Select Progress
          Case #PB_Http_Success
            *Tile\Size = FinishHTTP(*Tile\Download) ; \Size signals that the download is OK
            MyDebug(" Thread nb " + Str(*Tile\GetImageThread) + " " + *Tile\key + " for image " + *Tile\CacheFile + " finished. Size : " + Str(*Tile\Size), 5)
            Quit = #True
          Case #PB_Http_Failed
            FinishHTTP(*Tile\Download)
            *Tile\Size = 0 ; \Size = 0 signals that the download has failed
            MyDebug(" Thread nb " + Str(*Tile\GetImageThread) + " " + *Tile\key + "  for image " + *Tile\CacheFile + " failed.", 5)
            Quit = #True
          Case #PB_Http_Aborted
            FinishHTTP(*Tile\Download)
            *Tile\Size = 0 ; \Size = 0 signals that the download has failed
            MyDebug(" Thread nb " + Str(*Tile\GetImageThread) + " " + *Tile\key + "  for image " + *Tile\CacheFile + " aborted.", 5)
            Quit = #True
          Default
            MyDebug(" Thread nb " + Str(*Tile\GetImageThread) + " " + *Tile\key + "  for image " + *Tile\CacheFile + " downloading " + Str(Progress) + " bytes", 5)
            If ElapsedMilliseconds() - *Tile\Time > 10000
              MyDebug(" Thread nb " + Str(*Tile\GetImageThread) + " " + *Tile\key + "  for image " + *Tile\CacheFile + " canceled after 10 seconds.", 5)
              AbortHTTP(*Tile\Download)
            EndIf
        EndSelect
        Delay(200) ; Frees CPU
      Until Quit
    EndIf
    ; End of the memory cache access
    ;LockMutex(*PBMap\MemoryCacheAccessMutex)
    PostEvent(#PB_Event_Gadget, *Tile\Window, *Tile\Gadget, #PB_MAP_TILE_CLEANUP, *Tile) ; To free memory outside the thread
    ;UnlockMutex(*PBMap\MemoryCacheAccessMutex)
  EndProcedure
  
  ;-***
  
  Procedure.i GetTile(key.s, URL.s, CacheFile.s)
    ; MemoryCache access management
    LockMutex(*PBMap\MemoryCacheAccessMutex)
    ; Try to find the tile in memory cache
    Protected *timg.ImgMemCach = FindMapElement(*PBMap\MemCache\Images(), key)
    If *timg
      MyDebug("Key : " + key + " found in memory cache", 4)
      ; Is the associated image already been loaded in memory ?
      If *timg\nImage
        ; Yes, returns the image's nb
        MyDebug(" as image " + *timg\nImage, 4)
        ; *** Cache management
        ; Retrieves the image in the time stack, push it to the end (to say it's the lastly used)
        ChangeCurrentElement(*PBMap\MemCache\ImagesTimeStack(), *timg\TimeStackPtr)
        MoveElement(*PBMap\MemCache\ImagesTimeStack(), #PB_List_Last)
        ; *timg\TimeStackPtr = LastElement(*PBMap\MemCache\ImagesTimeStack())
        ; ***
        UnlockMutex(*PBMap\MemoryCacheAccessMutex)
        ProcedureReturn *timg
      Else
        ; No, try to load it from HD (see below)
        MyDebug(" but not the image.", 4)
      EndIf
    Else
      ; The tile has not been found in the cache, so creates a new cache element 
      *timg = AddMapElement(*PBMap\MemCache\Images(), key)
      If *timg = 0
        MyDebug("  Can't add a new cache element.", 4)
        UnlockMutex(*PBMap\MemoryCacheAccessMutex)
        ProcedureReturn #False
      EndIf
      ; add a new time stack element at the End     
      LastElement(*PBMap\MemCache\ImagesTimeStack())
      ; Stores the time stack ptr   
      *timg\TimeStackPtr = AddElement(*PBMap\MemCache\ImagesTimeStack())
      If *timg\TimeStackPtr = 0
        MyDebug("  Can't add a new time stack element.", 4)
        DeleteMapElement(*PBMap\MemCache\Images())
        UnlockMutex(*PBMap\MemoryCacheAccessMutex)
        ProcedureReturn #False
      EndIf
      ; Associates the time stack element to the cache element
      *PBMap\MemCache\ImagesTimeStack()\MapKey = MapKey(*PBMap\MemCache\Images())    
      MyDebug("Key : " + key + " added in memory cache", 4)
    EndIf
    ; If there's no active download thread for this tile
    If *timg\Tile <= 0      
      *timg\nImage = 0
      *timg\Size = FileSize(CacheFile)        
      ; Manage tile file lifetime, delete if too old, or if size = 0
      If *PBMap\Options\TileLifetime <> -1 
        If *timg\Size >= 0 ; Does the file exists ?
          If *timg\Size = 0 Or (Date() - GetFileDate(CacheFile, #PB_Date_Modified) > *PBMap\Options\TileLifetime) ; If Lifetime > MaxLifeTime ; There's a bug with #PB_Date_Created
            If DeleteFile(CacheFile)
              MyDebug("  Deleting image file  " + CacheFile, 3)
              *timg\Size = 0
            Else
              MyDebug("  Can't delete image file  " + CacheFile, 3)
              UnlockMutex(*PBMap\MemoryCacheAccessMutex)
              ProcedureReturn #False
            EndIf
          EndIf
        EndIf
      EndIf
      ; Try To load it from HD
      If *timg\Size > 0   
        *timg\nImage = GetTileFromHDD(CacheFile.s)
      Else
        MyDebug(" Failed loading from HDD " + CacheFile + " -> Filesize = " + FileSize(CacheFile), 3)
      EndIf
      If *timg\nImage
        ; Image found and loaded from HDD
        *timg\Alpha = 0
        UnlockMutex(*PBMap\MemoryCacheAccessMutex)
        ProcedureReturn *timg
      Else
        ; If GetTileFromHDD failed, will load it (again?) from the web
        If *PBMap\ThreadsNB < *PBMap\Options\MaxThreads
          If *PBMap\DownloadSlots < *PBMap\Options\MaxDownloadSlots        
            ; Launch a new web loading thread
            *PBMap\DownloadSlots + 1
            Protected *NewTile.Tile = AllocateMemory(SizeOf(Tile))
            If *NewTile
              With *NewTile 
                ; New tile parameters
                \key = key
                \URL = URL
                \CacheFile = CacheFile
                \nImage = 0 
                \Time = ElapsedMilliseconds()
                \Window = *PBMap\Window 
                \Gadget = *PBMap\Gadget 
                \GetImageThread = CreateThread(@GetImageThread(), *NewTile)
                If \GetImageThread
                  *timg\Tile = *NewTile ; There's now a loading thread
                  *timg\Alpha = 0
                  MyDebug(" Creating get image thread nb " + Str(\GetImageThread) + " to get " + CacheFile + " (key = " + key, 3)
                  *PBMap\ThreadsNB + 1
                Else
                  MyDebug(" Can't create get image thread to get " + CacheFile, 3)
                  FreeMemory(*NewTile)
                EndIf
              EndWith
            Else        
              MyDebug(" Error, can't allocate memory for a new tile loading thread", 3)
            EndIf            
          Else
            MyDebug(" Thread needed " + key + "  for image " + CacheFile + " canceled because no free download slot.", 5)
          EndIf
        Else
          MyDebug(" Error, maximum threads nb reached", 3)
        EndIf
      EndIf
    EndIf
    UnlockMutex(*PBMap\MemoryCacheAccessMutex)
    ProcedureReturn #False
  EndProcedure
  
  Procedure DrawTiles(*Drawing.DrawingParameters, LayerName.s)
    Protected x.i, y.i, kq.q
    Protected tx.i = Int(*Drawing\TileCoordinates\x)          ; Don't forget the Int() !
    Protected ty.i = Int(*Drawing\TileCoordinates\y)
    Protected nx.i = *Drawing\RadiusX / *PBMap\TileSize        ; How many tiles around the point
    Protected ny.i = *Drawing\RadiusY / *PBMap\TileSize
    Protected px.i, py.i, *timg.ImgMemCach, tilex.i, tiley.i, key.s
    Protected URL.s, CacheFile.s
    Protected tilemax.i = 1<<*PBMap\Zoom
    Protected HereLoadBalancing.b                           ; Here is providing a load balancing system
    FindMapElement(*PBMap\Layers(), LayerName)
    MyDebug("Drawing tiles")
    For y = - ny - 1 To ny + 1
      For x = - nx - 1 To nx + 1
        px = *Drawing\RadiusX + x * *PBMap\TileSize - *Drawing\DeltaX
        py = *Drawing\RadiusY + y * *PBMap\TileSize - *Drawing\DeltaY
        tilex = (tx + x) % tilemax
        If tilex < 0
          tilex + tilemax
        EndIf
        tiley = ty + y 
        If tiley >= 0 And tiley < tilemax
          kq = (*PBMap\Zoom << 8) | (tilex << 16) | (tiley << 36)
          key = LayerName + Str(kq)
          ; Creates the cache tree based on the OSM tree+Layer : layer/zoom/x/y.png
          Protected DirName.s = *PBMap\Options\HDDCachePath + LayerName
          If FileSize(DirName) <> -2
            If CreateDirectory(DirName) = #False ; Creates a directory based on the layer name
              Error("Can't create the following layer directory : " + DirName)
            Else
              MyDebug(DirName + " successfully created", 4)
            EndIf
          EndIf
          ; Creates the sub-directory based on the zoom
          DirName + slash + Str(*PBMap\Zoom)
          If FileSize(DirName) <> -2
            If CreateDirectory(DirName) = #False 
              Error("Can't create the following zoom directory : " + DirName)
            Else
              MyDebug(DirName + " successfully created", 4)
            EndIf
          EndIf          
          ; Creates the sub-directory based on x
          DirName.s + slash + Str(tilex)
          If FileSize(DirName) <> -2
            If CreateDirectory(DirName) = #False 
              Error("Can't create the following x directory : " + DirName)
            Else
              MyDebug(DirName + " successfully created", 4)
            EndIf
          EndIf
          With *PBMap\Layers()
            Select \LayerType
                ;---- OSM tiles
              Case 0 
                URL = \ServerURL + Str(*PBMap\Zoom) + "/" + Str(tilex) + "/" + Str(tiley) + ".png"   
                ; Tile cache name based on y
                CacheFile = DirName + slash + Str(tiley) + ".png" 
                ;---- Here tiles
              Case 1 
                HereLoadBalancing = 1 + ((tiley + tilex) % 4)
                ; {Base URL}{Path}{resource (tile type)}/{Map id}/{scheme}/{zoom}/{column}/{row}/{size}/{format}?app_id={YOUR_APP_ID}&app_code={YOUR_APP_CODE}&{param}={value}
                URL = "https://" + StrU(HereLoadBalancing, #PB_Byte) + "." + \ServerURL + \path + \ressource + "/" + \id + "/" + \scheme + "/" + Str(*PBMap\Zoom) + "/" + Str(tilex) + "/" + Str(tiley) + "/256/" + \format + "?app_id=" + \APP_ID + "&app_code=" + \APP_CODE + "&lg=" + \lg + "&lg2=" + \lg2
                If \param <> ""
                  URL + "&" + \param
                EndIf
                ; Tile cache name based on y
                CacheFile = DirName + slash + Str(tiley) + "." + \format 
                ;---- GeoServer / geowebcache - google maps service tiles
              Case 2 
                ; template 'http://localhost:8080/geowebcache/service/gmaps?layers=layer-name&zoom={Z}&x={X}&y={Y}&format=image/png'
                URL = \ServerURL + \path + "?layers=" + \ServerLayerName + "&zoom={" + Str(*PBMap\Zoom) + "}&x={" + Str(tilex) + "}&y={" + Str(tiley) + "}&format=" + \format
                ; Tile cache name based on y
                CacheFile = DirName + slash + Str(tiley) + ".png" 
            EndSelect          
          EndWith
          *timg = GetTile(key, URL, CacheFile)
          If *timg And *timg\nImage
            If *PBMap\CallBackDrawTile
              ;CallFunctionFast(*PBMap\CallBackDrawTile, px, py, *timg\nImage)
              *PBMap\CallBackDrawTile(px, py, *timg\nImage, *PBMap\Layers()\Alpha)
              *PBMap\Redraw = #True
            Else
              MovePathCursor(px, py)
              If *timg\Alpha <= 224
                DrawVectorImage(ImageID(*timg\nImage), *timg\Alpha * *PBMap\Layers()\Alpha)
                *timg\Alpha + 32
                *PBMap\Redraw = #True
              Else
                DrawVectorImage(ImageID(*timg\nImage), 255 * *PBMap\Layers()\Alpha)
                *timg\Alpha = 256
              EndIf
            EndIf
          Else 
            MovePathCursor(px, py)
            DrawVectorImage(ImageID(*PBMap\ImgLoading), 255 * *PBMap\Layers()\Alpha)
          EndIf
        Else
          ; If *PBMap\Layers()\Name = ""
          MovePathCursor(px, py)
          DrawVectorImage(ImageID(*PBMap\ImgNothing), 255 * *PBMap\Layers()\Alpha)
          ; EndIf
        EndIf
        If *PBMap\Options\ShowDebugInfos
          VectorFont(FontID(*PBMap\StandardFont), 16)
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
    If *PBMap\CallBackMainPointer > 0
      ; @Procedure(X.i, Y.i) to DrawPointer (you must use VectorDrawing lib)
      CallFunctionFast(*PBMap\CallBackMainPointer, *Drawing\RadiusX, *Drawing\RadiusY)
    Else 
      VectorSourceColor(RGBA($FF, 0, 0, $FF))
      MovePathCursor(*Drawing\RadiusX, *Drawing\RadiusY)
      AddPathLine(-8, -16, #PB_Path_Relative)
      AddPathCircle(8, 0, 8, 180, 0, #PB_Path_Relative)
      AddPathLine(-8, 16, #PB_Path_Relative)
      AddPathCircle(0, -16, 5, 0, 360, #PB_Path_Relative)
      VectorSourceColor(RGBA($FF, 0, 0, $FF))
      FillPath(#PB_Path_Preserve):VectorSourceColor(RGBA($FF, 0, 0, $FF)); RGBA(0, 0, 0, 255)) 
      StrokePath(1)
    EndIf  
  EndProcedure
  
  Procedure DrawScale(*Drawing.DrawingParameters,x,y,alpha=80)
    Protected sunit.s 
    Protected Scale.d= 40075*Cos(Radian(*PBMap\GeographicCoordinates\Latitude))/Pow(2,*PBMap\Zoom) / 2   
    Select *PBMap\Options\ScaleUnit 
      Case #SCALE_Nautical
        Scale * 0.539957 
        sunit = " Nm"
      Case #SCALE_KM; 
        sunit = " Km"
    EndSelect
    VectorFont(FontID(*PBMap\StandardFont), 10)
    VectorSourceColor(RGBA(0, 0, 0, alpha))
    MovePathCursor(x,y)
    DrawVectorText(StrD(Scale,3)+sunit)
    MovePathCursor(x,y+12) 
    AddPathLine(x+128,y+12)
    StrokePath(1)
  EndProcedure
  
  Procedure DrawDegrees(*Drawing.DrawingParameters, alpha=192) 
    Protected nx, ny, nx1, ny1, x, y
    Protected pos1.PixelCoordinates, pos2.PixelCoordinates, Degrees1.GeographicCoordinates, degrees2.GeographicCoordinates 
    CopyStructure(*Drawing\Bounds\NorthWest, @Degrees1, GeographicCoordinates)
    CopyStructure(*Drawing\Bounds\SouthEast, @Degrees2, GeographicCoordinates)
    ; ensure we stay positive for the drawing
    nx =  Mod(Mod(Round(Degrees1\Longitude, #PB_Round_Down)-1, 360) + 360, 360)
    ny =          Round(Degrees1\Latitude,  #PB_Round_Up)  +1
    nx1 = Mod(Mod(Round(Degrees2\Longitude, #PB_Round_Up)  +1, 360) + 360, 360)
    ny1 =         Round(Degrees2\Latitude,  #PB_Round_Down)-1 
    Degrees1\Longitude = nx
    Degrees1\Latitude  = ny 
    Degrees2\Longitude = nx1
    Degrees2\Latitude  = ny1
    ; Debug "NW : " + StrD(Degrees1\Longitude) + " ; NE : " + StrD(Degrees2\Longitude)
    LatLon2PixelRel(@Degrees1, @pos1, *PBMap\Zoom)
    LatLon2PixelRel(@Degrees2, @pos2, *PBMap\Zoom)
    VectorFont(FontID(*PBMap\StandardFont), 10)
    VectorSourceColor(RGBA(0, 0, 0, alpha))    
    ; draw latitudes
    For y = ny1 To ny
      Degrees1\Longitude = nx
      Degrees1\Latitude  = y 
      LatLon2PixelRel(@Degrees1, @pos1, *PBMap\Zoom)
      MovePathCursor(pos1\x, pos1\y) 
      AddPathLine(   pos2\x, pos1\y)
      MovePathCursor(10, pos1\y) 
      DrawVectorText(StrD(y, 1))
    Next       
    ; draw longitudes
    x = nx
    Repeat
      Degrees1\Longitude = x
      Degrees1\Latitude  = ny
      LatLon2PixelRel(@Degrees1, @pos1, *PBMap\Zoom)
      MovePathCursor(pos1\x, pos1\y)
      AddPathLine(   pos1\x, pos2\y) 
      MovePathCursor(pos1\x,10) 
      DrawVectorText(StrD(Mod(x + 180, 360) - 180, 1))
      x = (x + 1)%360
    Until x = nx1
    StrokePath(1)  
  EndProcedure   
  
  Procedure DrawZoom(x.i, y.i)
    VectorFont(FontID(*PBMap\StandardFont), 20)
    VectorSourceColor(RGBA(0, 0, 0,150))
    MovePathCursor(x,y)
    DrawVectorText(Str(GetZoom()))
  EndProcedure
  ;-*** Tracks
  
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
    VectorFont(FontID(*PBMap\StandardFont), 13)
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
    VectorFont(FontID(*PBMap\StandardFont), 14)
    MovePathCursor(x-VectorTextWidth(Str(dist))/2, y-24-VectorTextHeight(Str(dist))/2)
    VectorSourceColor(RGBA(0, 0, 0, 255))
    DrawVectorText(Str(dist))
  EndProcedure
  
  Procedure DeleteTrack(*Ptr)
    If *Ptr 
      ChangeCurrentElement(*PBMap\TracksList(), *Ptr)
      DeleteElement(*PBMap\TracksList())
    EndIf
  EndProcedure
  
  Procedure DeleteSelectedTracks()
    ForEach *PBMap\TracksList()
      If *PBMap\TracksList()\Selected
        DeleteElement(*PBMap\TracksList())
        *PBMap\Redraw = #True
      EndIf
    Next
  EndProcedure
  
  Procedure ClearTracks()
    ClearList(*PBMap\TracksList())
    *PBMap\Redraw = #True  
  EndProcedure
  
  Procedure SetTrackColour(*Ptr, Colour.i)
    If *Ptr 
      ChangeCurrentElement(*PBMap\TracksList(), *Ptr)
      *PBMap\TracksList()\Colour = Colour
      *PBMap\Redraw = #True
    EndIf
  EndProcedure
  
  Procedure  DrawTracks(*Drawing.DrawingParameters)
    Protected Pixel.PixelCoordinates
    Protected Location.GeographicCoordinates
    Protected km.f, memKm.i
    With *PBMap\TracksList()
      ; Trace Track
      If ListSize(*PBMap\TracksList()) > 0
        BeginVectorLayer()
        ForEach *PBMap\TracksList()
          If ListSize(\Track()) > 0
            ; Check visibility
            \Visible = #False
            ForEach \Track()
              If IsInDrawingPixelBoundaries(*Drawing, @*PBMap\TracksList()\Track())
                \Visible = #True
                Break
              EndIf
            Next
            If \Visible
              ; Draw tracks
              ForEach \Track()
                LatLon2PixelRel(@*PBMap\TracksList()\Track(),  @Pixel, *PBMap\Zoom)
                If ListIndex(\Track()) = 0
                  MovePathCursor(Pixel\x, Pixel\y)
                Else
                  AddPathLine(Pixel\x, Pixel\y)    
                EndIf
              Next
              ; \BoundingBox\x = PathBoundsX()
              ; \BoundingBox\y = PathBoundsY()
              ; \BoundingBox\w = PathBoundsWidth()
              ; \BoundingBox\h = PathBoundsHeight()
              If \Focus
                VectorSourceColor(*PBMap\Options\ColourFocus)
              ElseIf \Selected
                VectorSourceColor(*PBMap\Options\ColourSelected)
              Else
                VectorSourceColor(\Colour)
              EndIf
              StrokePath(\StrokeWidth, #PB_Path_RoundEnd|#PB_Path_RoundCorner)
              
              ; YA pour marquer chaque point d'un rond
              ForEach \Track()
                LatLon2PixelRel(@*PBMap\TracksList()\Track(),  @Pixel, *PBMap\Zoom)
                AddPathCircle(Pixel\x,Pixel\y,(\StrokeWidth / 4))
              Next
              VectorSourceColor(RGBA(255, 255, 0, 255))
              StrokePath(1)
              
            EndIf  
          EndIf
        Next
        EndVectorLayer()
        ;Draw distances
        If *PBMap\Options\ShowTrackKms And *PBMap\Zoom > 10
          BeginVectorLayer()
          ForEach *PBMap\TracksList()
            If \Visible
              km = 0 : memKm = -1
              ForEach *PBMap\TracksList()\Track()
                ; Test Distance
                If ListIndex(\Track()) = 0
                  Location\Latitude = \Track()\Latitude
                  Location\Longitude = \Track()\Longitude 
                Else 
                  km = km + HaversineInKM(@Location, @*PBMap\TracksList()\Track())
                  Location\Latitude = \Track()\Latitude
                  Location\Longitude = \Track()\Longitude 
                EndIf
                LatLon2PixelRel(@*PBMap\TracksList()\Track(), @Pixel, *PBMap\Zoom)
                If Int(km) <> memKm
                  memKm = Int(km)
                  If Int(km) = 0
                    DrawTrackPointerFirst(Pixel\x , Pixel\y, Int(km))
                  Else
                    DrawTrackPointer(Pixel\x , Pixel\y, Int(km))
                  EndIf
                EndIf
              Next
            EndIf
          Next
          EndVectorLayer()
        EndIf
      EndIf
    EndWith
  EndProcedure
  
  Procedure.i LoadGpxFile(FileName.s)
    If LoadXML(0, FileName.s)
      Protected Message.s
      If XMLStatus(0) <> #PB_XML_Success
        Message = "Error in the XML file:" + Chr(13)
        Message + "Message: " + XMLError(0) + Chr(13)
        Message + "Line: " + Str(XMLErrorLine(0)) + "   Character: " + Str(XMLErrorPosition(0))
        Error(Message)
      EndIf
      Protected *MainNode,*subNode,*child,child.l
      *MainNode = MainXMLNode(0)
      *MainNode = XMLNodeFromPath(*MainNode, "/gpx/trk/trkseg")
      Protected *NewTrack.Tracks = AddElement(*PBMap\TracksList())
      *PBMap\TracksList()\StrokeWidth = *PBMap\Options\StrokeWidthTrackDefault
      *PBMap\TracksList()\Colour      = *PBMap\Options\ColourTrackDefault
      For child = 1 To XMLChildCount(*MainNode)
        *child = ChildXMLNode(*MainNode, child)
        AddElement(*NewTrack\Track())
        If ExamineXMLAttributes(*child)
          While NextXMLAttribute(*child)
            Select XMLAttributeName(*child)
              Case "lat"
                *NewTrack\Track()\Latitude = ValD(XMLAttributeValue(*child))
              Case "lon"
                *NewTrack\Track()\Longitude = ValD(XMLAttributeValue(*child))
            EndSelect
          Wend
        EndIf
      Next 
      SetZoomToTracks(LastElement(*PBMap\TracksList())) ; <-To center the view, and zoom on the tracks  
      ProcedureReturn *NewTrack  
    EndIf
  EndProcedure
  
  Procedure.i SaveGpxFile(FileName.s, *Track.Tracks)
    Protected Message.s
    If CreateXML(0)
      Protected *MainNode, *subNode, *child
      *MainNode = CreateXMLNode(RootXMLNode(0), "gpx")
      *subNode = CreateXMLNode(*MainNode, "trk")
      *subNode = CreateXMLNode(*subNode, "trkseg")
      ForEach *Track\Track()
        *child = CreateXMLNode(*subNode, "trkpt")
        SetXMLAttribute(*child, "lat", StrD(*Track\Track()\Latitude))
        SetXMLAttribute(*child, "lon", StrD(*Track\Track()\Longitude))
      Next
      SaveXML(0, FileName)
      If XMLStatus(0) <> #PB_XML_Success
        Message = "Error in the XML file:" + Chr(13)
        Message + "Message: " + XMLError(0) + Chr(13)
        Message + "Line: " + Str(XMLErrorLine(0)) + "   Character: " + Str(XMLErrorPosition(0))
        Error(Message)
        ProcedureReturn #False
      EndIf
      ProcedureReturn #True  
    Else
      ProcedureReturn #False
    EndIf
  EndProcedure  
  
  ;-*** Markers
  
  Procedure ClearMarkers()
    ClearList(*PBMap\Markers())
    *PBMap\Redraw = #True  
  EndProcedure
  
  Procedure DeleteMarker(*Ptr)
    If *Ptr 
      ChangeCurrentElement(*PBMap\Markers(), *Ptr)
      DeleteElement(*PBMap\Markers())
      *PBMap\Redraw = #True
    EndIf
  EndProcedure
  
  Procedure DeleteSelectedMarkers()
    ForEach *PBMap\Markers()
      If *PBMap\Markers()\Selected
        DeleteElement(*PBMap\Markers())
        *PBMap\Redraw = #True
      EndIf
    Next
  EndProcedure
  
  Procedure.i AddMarker(Latitude.d, Longitude.d, Identifier.s = "", Legend.s = "", Color.l=-1, CallBackPointer.i = -1)
    Protected *Ptr = AddElement(*PBMap\Markers())
    If *Ptr 
      *PBMap\Markers()\GeographicCoordinates\Latitude = Latitude
      *PBMap\Markers()\GeographicCoordinates\Longitude = ClipLongitude(Longitude)
      *PBMap\Markers()\Identifier = Identifier
      *PBMap\Markers()\Legend = Legend
      *PBMap\Markers()\Color = Color
      *PBMap\Markers()\CallBackPointer = CallBackPointer
      *PBMap\Redraw = #True
      ProcedureReturn *Ptr
    EndIf
  EndProcedure
  
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
    ForEach *PBMap\Markers()
      If *PBMap\Markers()\EditWindow = EventWindow()
        *PBMap\Markers()\EditWindow = 0
      EndIf
    Next
    CloseWindow(EventWindow())  
  EndProcedure
  
  Procedure MarkerEdit(*Marker.Marker)
    If *Marker\EditWindow = 0 ; Check that this marker has no already opened window
      Protected WindowMarkerEdit = OpenWindow(#PB_Any, WindowX(*PBMap\Window) + WindowWidth(*PBMap\Window) / 2 - 150, WindowY(*PBMap\Window)+ WindowHeight(*PBMap\Window) / 2 + 50, 300, 100, "Marker Edit", #PB_Window_SystemMenu | #PB_Window_TitleBar)
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
  
  Procedure DrawMarker(x.i, y.i, Nb.i, *Marker.Marker)
    Protected Text.s
    VectorSourceColor(*Marker\Color)
    MovePathCursor(x, y)
    AddPathLine(-8, -16, #PB_Path_Relative)
    AddPathCircle(8, 0, 8, 180, 0, #PB_Path_Relative)
    AddPathLine(-8, 16, #PB_Path_Relative)
    ; FillPath(#PB_Path_Preserve) 
    ; ClipPath(#PB_Path_Preserve)
    AddPathCircle(0, -16, 5, 0, 360, #PB_Path_Relative)
    VectorSourceColor(*Marker\Color)
    FillPath(#PB_Path_Preserve)
    If *Marker\Focus
      VectorSourceColor(*PBMap\Options\ColourFocus)
      StrokePath(3)
    ElseIf *Marker\Selected
      VectorSourceColor(*PBMap\Options\ColourSelected)
      StrokePath(4)
    Else
      VectorSourceColor(*Marker\Color)
      StrokePath(1)
    EndIf
    If *PBMap\Options\ShowMarkersNb
      If *Marker\Identifier = ""
        Text.s = Str(Nb)
      Else
        Text.s = *Marker\Identifier
      EndIf
      VectorFont(FontID(*PBMap\StandardFont), 13)
      MovePathCursor(x - VectorTextWidth(Text) / 2, y)
      VectorSourceColor(RGBA(0, 0, 0, 255))
      DrawVectorText(Text)
    EndIf
    If *PBMap\Options\ShowMarkersLegend And *Marker\Legend <> ""
      VectorFont(FontID(*PBMap\StandardFont), 13)
      ; dessin d'un cadre avec fond transparent
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
    ForEach *PBMap\Markers()
      If IsInDrawingPixelBoundaries(*Drawing, @*PBMap\Markers()\GeographicCoordinates)
        LatLon2PixelRel(@*PBMap\Markers()\GeographicCoordinates, @Pixel, *PBMap\Zoom)
        If *PBMap\Markers()\CallBackPointer > 0
          CallFunctionFast(*PBMap\Markers()\CallBackPointer, Pixel\x, Pixel\y, *PBMap\Markers()\Focus, *PBMap\Markers()\Selected)
        Else
          DrawMarker(Pixel\x, Pixel\y, ListIndex(*PBMap\Markers()), @*PBMap\Markers())
        EndIf
      EndIf 
    Next
  EndProcedure 
  
  ;-*** Main drawing stuff
  
  Procedure DrawDebugInfos(*Drawing.DrawingParameters)
    ; Display how many images in cache
    VectorFont(FontID(*PBMap\StandardFont), 16)
    VectorSourceColor(RGBA(0, 0, 0, 80))
    MovePathCursor(50, 50)
    DrawVectorText("Images in cache : " + Str(MapSize(*PBMap\MemCache\Images())))
    MovePathCursor(50, 70)
    Protected ThreadCounter = 0
    ForEach *PBMap\MemCache\Images()
      If *PBMap\MemCache\Images()\Tile > 0
        If IsThread(*PBMap\MemCache\Images()\Tile\GetImageThread)
          ThreadCounter + 1
        EndIf
      EndIf
    Next
    DrawVectorText("Threads nb : " + Str(ThreadCounter))    
    MovePathCursor(50, 90)
    DrawVectorText("Zoom : " + Str(*PBMap\Zoom))
    MovePathCursor(50, 110)
    DrawVectorText("Lat-Lon 1 : " + StrD(*Drawing\Bounds\NorthWest\Latitude) + "," + StrD(*Drawing\Bounds\NorthWest\Longitude))  
    MovePathCursor(50, 130)
    DrawVectorText("Lat-Lon 2 : " + StrD(*Drawing\Bounds\SouthEast\Latitude) + "," + StrD(*Drawing\Bounds\SouthEast\Longitude))  
  EndProcedure
  
  Procedure DrawOSMCopyright(*Drawing.DrawingParameters)
    Protected Text.s = "© OpenStreetMap contributors"
    VectorFont(FontID(*PBMap\StandardFont), 12)
    VectorSourceColor(RGBA(0, 0, 0, 80))
    MovePathCursor(GadgetWidth(*PBMap\Gadget) - VectorTextWidth(Text), GadgetHeight(*PBMap\Gadget) - 20)
    DrawVectorText(Text)
  EndProcedure
  
  Procedure Drawing()
    Protected *Drawing.DrawingParameters = @*PBMap\Drawing
    Protected PixelCenter.PixelCoordinates
    Protected Px.d, Py.d,a, ts = *PBMap\TileSize, nx, ny
    Protected LayerOrder.i = 0
    Protected NW.Coordinates, SE.Coordinates
    Protected OSMCopyright.i = #False
    *PBMap\Dirty = #False
    *PBMap\Redraw = #False
    ; *** Precalc some values
    *Drawing\RadiusX = GadgetWidth(*PBMap\Gadget) / 2
    *Drawing\RadiusY = GadgetHeight(*PBMap\Gadget) / 2
    *Drawing\GeographicCoordinates\Latitude = *PBMap\GeographicCoordinates\Latitude
    *Drawing\GeographicCoordinates\Longitude = *PBMap\GeographicCoordinates\Longitude
    LatLon2TileXY(*Drawing\GeographicCoordinates, *Drawing\TileCoordinates, *PBMap\Zoom)
    LatLon2Pixel(*Drawing\GeographicCoordinates, @PixelCenter, *PBMap\Zoom)
    ; Pixel shift, aka position in the tile
    Px = *Drawing\TileCoordinates\x 
    Py = *Drawing\TileCoordinates\y
    *Drawing\DeltaX = Px * ts - (Int(Px) * ts) ; Don't forget the Int() !
    *Drawing\DeltaY = Py * ts - (Int(Py) * ts)
    ; Drawing boundaries  
    nx = *Drawing\RadiusX / ts ; How many tiles around the point
    ny = *Drawing\RadiusY / ts
    NW\x = Px - nx - 1
    NW\y = Py - ny - 1
    SE\x = Px + nx + 2 
    SE\y = Py + ny + 2
    TileXY2LatLon(@NW, *Drawing\Bounds\NorthWest, *PBMap\Zoom)
    TileXY2LatLon(@SE, *Drawing\Bounds\SouthEast, *PBMap\Zoom)
    ; *Drawing\Width = (SE\x / Pow(2, *PBMap\Zoom) * 360.0) - (NW\x / Pow(2, *PBMap\Zoom) * 360.0) ; Calculus without clipping
    ; *Drawing\Height = *Drawing\Bounds\NorthWest\Latitude - *Drawing\Bounds\SouthEast\Latitude
    ; ***
    ; Main drawing stuff
    StartVectorDrawing(CanvasVectorOutput(*PBMap\Gadget))
    ; Clearscreen
    VectorSourceColor(RGBA(150, 150, 150, 255))
    FillVectorOutput()
    ; TODO add in layers of tiles ; this way we can cache them as 0 base 1.n layers 
    ; such as for openseamap tiles which are overlaid. not that efficent from here though.
    ; Draws layers based on their number
    ForEach *PBMap\LayersList()
      If *PBMap\LayersList()\Enabled
        DrawTiles(*Drawing, *PBMap\LayersList()\Name)
      EndIf
      If *PBMap\LayersList()\LayerType = 0 ; OSM
        OSMCopyright = #True
      EndIf
    Next   
    If *PBMap\Options\ShowTrack
      DrawTracks(*Drawing)
    EndIf
    If *PBMap\Options\ShowMarkers
      DrawMarkers(*Drawing)
    EndIf
    If *PBMap\Options\ShowDegrees And *PBMap\Zoom > 2
      DrawDegrees(*Drawing, 192)    
    EndIf    
    If *PBMap\Options\ShowPointer
      DrawPointer(*Drawing)
    EndIf
    If *PBMap\Options\ShowDebugInfos
      DrawDebugInfos(*Drawing)
    EndIf
    If *PBMap\Options\ShowScale
      DrawScale(*Drawing, 10, GadgetHeight(*PBMap\Gadget) - 20, 192)
    EndIf
    If *PBMap\Options\ShowZoom
      DrawZoom(GadgetWidth(*PBMap\Gadget) - 30, 5) ; ajout YA - affiche le niveau de zoom
    EndIf
    If OSMCopyright
      DrawOSMCopyright(*Drawing)
    EndIf
    StopVectorDrawing()
  EndProcedure
  
  Procedure Refresh()
    *PBMap\Redraw = #True
    ; Drawing()
  EndProcedure
  
  ;-*** Misc functions
  
  Procedure.d GetMouseLongitude()
    Protected MouseX.d = (*PBMap\PixelCoordinates\x - *PBMap\Drawing\RadiusX + GetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_MouseX)) / *PBMap\TileSize
    Protected n.d = Pow(2.0, *PBMap\Zoom)
    ; double mod is to ensure the longitude to be in the range [-180; 180[
    ProcedureReturn Mod(Mod(MouseX / n * 360.0, 360.0) + 360.0, 360.0) - 180
  EndProcedure
  
  Procedure.d GetMouseLatitude()
    Protected MouseY.d = (*PBMap\PixelCoordinates\y - *PBMap\Drawing\RadiusY + GetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_MouseY)) / *PBMap\TileSize
    Protected n.d = Pow(2.0, *PBMap\Zoom)
    ProcedureReturn Degree(ATan(SinH(#PI * (1.0 - 2.0 * MouseY / n))))
  EndProcedure
  
  Procedure SetLocation(latitude.d, longitude.d, Zoom = -1, Mode.i = #PB_Absolute)
    Select Mode
      Case #PB_Absolute
        *PBMap\GeographicCoordinates\Latitude = latitude
        *PBMap\GeographicCoordinates\Longitude = longitude
        If Zoom <> -1 
          *PBMap\Zoom = Zoom
        EndIf
      Case #PB_Relative
        *PBMap\GeographicCoordinates\Latitude  + latitude
        *PBMap\GeographicCoordinates\Longitude + longitude
        If Zoom <> -1 
          *PBMap\Zoom + Zoom
        EndIf    
    EndSelect
    *PBMap\GeographicCoordinates\Longitude = ClipLongitude(*PBMap\GeographicCoordinates\Longitude)
    If *PBMap\GeographicCoordinates\Latitude < -89 
      *PBMap\GeographicCoordinates\Latitude = -89 
    EndIf
    If *PBMap\GeographicCoordinates\Latitude > 89
      *PBMap\GeographicCoordinates\Latitude = 89 
    EndIf
    If *PBMap\Zoom > *PBMap\ZoomMax : *PBMap\Zoom = *PBMap\ZoomMax : EndIf
    If *PBMap\Zoom < *PBMap\ZoomMin : *PBMap\Zoom = *PBMap\ZoomMin : EndIf
    LatLon2TileXY(@*PBMap\GeographicCoordinates, @*PBMap\Drawing\TileCoordinates, *PBMap\Zoom)
    ; Convert X, Y in tile.decimal into real pixels
    *PBMap\PixelCoordinates\x = *PBMap\Drawing\TileCoordinates\x * *PBMap\TileSize
    *PBMap\PixelCoordinates\y = *PBMap\Drawing\TileCoordinates\y * *PBMap\TileSize 
    *PBMap\Redraw = #True
    If *PBMap\CallBackLocation > 0
      CallFunctionFast(*PBMap\CallBackLocation, @*PBMap\GeographicCoordinates)
    EndIf 
  EndProcedure
  
  Procedure SetZoomToArea(MinY.d, MaxY.d, MinX.d, MaxX.d)
    ; Source => http://gis.stackexchange.com/questions/19632/how-to-calculate-the-optimal-zoom-level-to-display-two-or-more-points-on-a-map
    ; bounding box in long/lat coords (x=long, y=lat)
    Protected DeltaX.d = MaxX - MinX                            ; assumption ! In original code DeltaX have no source
    Protected centerX.d = MinX + DeltaX / 2                     ; assumption ! In original code CenterX have no source
    Protected paddingFactor.f= 1.2                              ; paddingFactor: this can be used to get the "120%" effect ThomM refers to. Value of 1.2 would get you the 120%.
    Protected ry1.d = Log((Sin(Radian(MinY)) + 1) / Cos(Radian(MinY)))
    Protected ry2.d = Log((Sin(Radian(MaxY)) + 1) / Cos(Radian(MaxY)))
    Protected ryc.d = (ry1 + ry2) / 2                                 
    Protected centerY.d = Degree(ATan(SinH(ryc)))                     
    Protected resolutionHorizontal.d = DeltaX / (*PBMap\Drawing\RadiusX * 2)
    Protected vy0.d = Log(Tan(#PI*(0.25 + centerY/360))); 
    Protected vy1.d = Log(Tan(#PI*(0.25 + MaxY/360)))   ; 
    Protected viewHeightHalf.d = *PBMap\Drawing\RadiusY  ; 
    Protected zoomFactorPowered.d = viewHeightHalf / (40.7436654315252*(vy1 - vy0))
    Protected resolutionVertical.d = 360.0 / (zoomFactorPowered * *PBMap\TileSize)    
    If resolutionHorizontal<>0 And resolutionVertical<>0
      Protected resolution.d = Max(resolutionHorizontal, resolutionVertical)* paddingFactor
      Protected zoom.d = Log(360 / (resolution * *PBMap\TileSize))/Log(2)
      Protected lon.d = centerX; 
      Protected lat.d = centerY; 
      SetLocation(lat, lon, Round(zoom,#PB_Round_Down))
    Else
      SetLocation(*PBMap\GeographicCoordinates\Latitude, *PBMap\GeographicCoordinates\Longitude, 15)
    EndIf
  EndProcedure
  
  Procedure  SetZoomToTracks(*Tracks.Tracks)
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
        SetZoomToArea(MinY.d, MaxY.d, MinX.d, MaxX.d)
      EndWith
    EndIf
  EndProcedure
  
  Procedure SetZoom(Zoom.i, mode.i = #PB_Relative)
    Select mode
      Case #PB_Relative
        *PBMap\Zoom = *PBMap\Zoom + zoom  
      Case #PB_Absolute
        *PBMap\Zoom = zoom
    EndSelect
    If *PBMap\Zoom > *PBMap\ZoomMax : *PBMap\Zoom = *PBMap\ZoomMax  : ProcedureReturn : EndIf
    If *PBMap\Zoom < *PBMap\ZoomMin : *PBMap\Zoom = *PBMap\ZoomMin  : ProcedureReturn : EndIf
    LatLon2TileXY(@*PBMap\GeographicCoordinates, @*PBMap\Drawing\TileCoordinates, *PBMap\Zoom)
    ; Convert X, Y in tile.decimal into real pixels
    *PBMap\PixelCoordinates\X = *PBMap\Drawing\TileCoordinates\x * *PBMap\TileSize
    *PBMap\PixelCoordinates\Y = *PBMap\Drawing\TileCoordinates\y * *PBMap\TileSize
    ; First drawing
    *PBMap\Redraw = #True
    If *PBMap\CallBackLocation > 0
      CallFunctionFast(*PBMap\CallBackLocation, @*PBMap\GeographicCoordinates)
    EndIf 
  EndProcedure
  
  Procedure SetAngle(Angle.d, Mode = #PB_Absolute) 
    If Mode = #PB_Absolute 
      *PBMap\Angle = Angle  
    Else 
      *PBMap\Angle + Angle 
      *PBMap\Angle = Mod(*PBMap\Angle,360)
    EndIf
    *PBMap\Redraw = #True
  EndProcedure
  
  ;-*** Callbacks
  
  Procedure SetCallBackLocation(CallBackLocation.i)
    *PBMap\CallBackLocation = CallBackLocation
  EndProcedure
  
  Procedure SetCallBackMainPointer(CallBackMainPointer.i)
    *PBMap\CallBackMainPointer = CallBackMainPointer
  EndProcedure
  
  Procedure SetCallBackMarker(CallBackLocation.i)
    *PBMap\CallBackMarker = CallBackLocation
  EndProcedure
  
  Procedure SetCallBackLeftClic(CallBackLocation.i)
    *PBMap\CallBackLeftClic = CallBackLocation
  EndProcedure
  
  Procedure SetCallBackDrawTile(CallBackLocation.i)
    *PBMap\CallBackDrawTile = CallBackLocation
  EndProcedure
  
  Procedure SetCallBackModifyTileFile(CallBackLocation.i)
    *PBMap\CallBackModifyTileFile = CallBackLocation
  EndProcedure
  
  ;***
  
  Procedure SetMapScaleUnit(ScaleUnit.i = PBMAP::#SCALE_KM)
    *PBMap\Options\ScaleUnit = ScaleUnit
    *PBMap\Redraw = #True
    ; Drawing()
  EndProcedure   
  
  ; User mode
  ; #MODE_DEFAULT = 0 -> "Hand" (move map) and move objects
  ; #MODE_HAND    = 1 -> Hand only
  ; #MODE_SELECT  = 2 -> Move objects only
  ; #MODE_EDIT    = 3 -> Create objects
  Procedure SetMode(Mode.i = #MODE_DEFAULT)
    *PBMap\Mode = Mode  
  EndProcedure
  
  Procedure.i GetMode()
    ProcedureReturn *PBMap\Mode
  EndProcedure
  
  ; Zoom on x, y pixel position from the center
  Procedure SetZoomOnPixel(x, y, zoom)
    ; *** First : Zoom
    *PBMap\Zoom + zoom
    If *PBMap\Zoom > *PBMap\ZoomMax : *PBMap\Zoom = *PBMap\ZoomMax : ProcedureReturn : EndIf
    If *PBMap\Zoom < *PBMap\ZoomMin : *PBMap\Zoom = *PBMap\ZoomMin : ProcedureReturn : EndIf
    LatLon2Pixel(@*PBMap\GeographicCoordinates, @*PBMap\PixelCoordinates, *PBMap\Zoom)
    If Zoom = 1
      *PBMap\PixelCoordinates\x + x
      *PBMap\PixelCoordinates\y + y
    ElseIf zoom = -1
      *PBMap\PixelCoordinates\x - x/2
      *PBMap\PixelCoordinates\y - y/2
    EndIf
    Pixel2LatLon(@*PBMap\PixelCoordinates, @*PBMap\GeographicCoordinates, *PBMap\Zoom)
    ; Start drawing
    *PBMap\Redraw = #True
    ; If CallBackLocation send Location To function
    If *PBMap\CallBackLocation > 0
      CallFunctionFast(*PBMap\CallBackLocation, @*PBMap\GeographicCoordinates)
    EndIf      
  EndProcedure  
  
  ; Zoom on x, y position relative to the canvas gadget
  Procedure SetZoomOnPixelRel(x, y, zoom)
    SetZoomOnPixel(x - *PBMap\Drawing\RadiusX, y - *PBMap\Drawing\RadiusY, zoom)
  EndProcedure  
  
  ; Go to x, y position relative to the canvas gadget left up
  Procedure GotoPixelRel(x, y)
    LatLon2Pixel(@*PBMap\GeographicCoordinates, @*PBMap\PixelCoordinates, *PBMap\Zoom)
    *PBMap\PixelCoordinates\x + x - *PBMap\Drawing\RadiusX
    *PBMap\PixelCoordinates\y + y - *PBMap\Drawing\RadiusY
    Pixel2LatLon(@*PBMap\PixelCoordinates, @*PBMap\GeographicCoordinates, *PBMap\Zoom)
    ; Start drawing
    *PBMap\Redraw = #True
    ; If CallBackLocation send Location to function
    If *PBMap\CallBackLocation > 0
      CallFunctionFast(*PBMap\CallBackLocation, @*PBMap\GeographicCoordinates)
    EndIf      
  EndProcedure  
  
  ; Go to x, y position relative to the canvas gadget
  Procedure GotoPixel(x, y)
    *PBMap\PixelCoordinates\x = x
    *PBMap\PixelCoordinates\y = y
    Pixel2LatLon(@*PBMap\PixelCoordinates, @*PBMap\GeographicCoordinates, *PBMap\Zoom)
    ; Start drawing
    *PBMap\Redraw = #True
    ; If CallBackLocation send Location to function
    If *PBMap\CallBackLocation > 0
      CallFunctionFast(*PBMap\CallBackLocation, @*PBMap\GeographicCoordinates)
    EndIf      
  EndProcedure  
  
  Procedure.d GetLatitude()
    ProcedureReturn *PBMap\GeographicCoordinates\Latitude
  EndProcedure
  
  Procedure.d GetLongitude()
    ProcedureReturn *PBMap\GeographicCoordinates\Longitude
  EndProcedure
  
  Procedure.i GetZoom()
    ProcedureReturn *PBMap\Zoom
  EndProcedure
  
  Procedure.d GetAngle()
    ProcedureReturn *PBMap\Angle
  EndProcedure
  
  Procedure NominatimGeoLocationQuery(Address.s, *ReturnPosition.GeographicCoordinates = 0)
    Protected Size.i
    Protected Query.s = "http://nominatim.openstreetmap.org/search/" + 
                        URLEncoder(Address) + 
                        "?format=json&addressdetails=0&polygon=0&limit=1"
    Protected JSONFileName.s = *PBMap\Options\HDDCachePath + "nominatimresponse.json"
    ; Protected *Buffer = CurlReceiveHTTPToMemory("http://nominatim.openstreetmap.org/search/Unter%20den%20Linden%201%20Berlin?format=json&addressdetails=1&limit=1&polygon_svg=1", *PBMap\Options\ProxyURL, *PBMap\Options\ProxyPort, *PBMap\Options\ProxyUser, *PBMap\Options\ProxyPassword)
    ; Debug *Buffer
    ; Debug MemorySize(*Buffer)
    ; Protected JSon.s = PeekS(*Buffer, MemorySize(*Buffer), #PB_UTF8)
    If *PBMap\Options\Proxy
      HTTPProxy(*PBMap\Options\ProxyURL + ":" + *PBMap\Options\ProxyPort, *PBMap\Options\ProxyUser, *PBMap\Options\ProxyPassword)
    EndIf
    Size = ReceiveHTTPFile(Query, JSONFileName)
    If LoadJSON(0, JSONFileName) = 0
      ; Demivec's code
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
      If lat <> "" And lon <> "" 
        SetZoomToArea(bbox\SouthEast\Latitude, bbox\NorthWest\Latitude, bbox\NorthWest\Longitude, bbox\SouthEast\Longitude)
        ; SetLocation(Position\Latitude, Position\Longitude)
      EndIf
    EndIf
  EndProcedure
  
  Procedure.i ClearDiskCache()
    If *PBMap\Options\Warning
      Protected Result.i = MessageRequester("Warning", "You will clear all cache content in " + *PBMap\Options\HDDCachePath + ". Are you sure ?",#PB_MessageRequester_YesNo)
      If Result = #PB_MessageRequester_No     ; Quit if "no" selected
        ProcedureReturn #False  
      EndIf
    EndIf
    If DeleteDirectory(*PBMap\Options\HDDCachePath, "", #PB_FileSystem_Recursive)
      MyDebug("Cache in : " + *PBMap\Options\HDDCachePath + " cleared", 3)
      CreateDirectoryEx(*PBMap\Options\HDDCachePath)
      ProcedureReturn #True
    Else
      MyDebug("Can't clear cache in " + *PBMap\Options\HDDCachePath, 3)
      ProcedureReturn #False
    EndIf
  EndProcedure
  
  ;-*** Main PBMap functions
  
  Procedure CanvasEvents()
    Protected CanvasMouseX.d, CanvasMouseY.d, MouseX.d, MouseY.d
    Protected MarkerCoords.PixelCoordinates, *Tile.Tile, MapWidth
    Protected key.s, Touch.i
    Protected Pixel.PixelCoordinates
    Protected ImgNB.i, TileNewFilename.s
    Static CtrlKey
    Protected Location.GeographicCoordinates
    
    Protected *PBMap.PBmap = PBMaps(Str(EventGadget()))
    MapWidth = Pow(2, *PBMap\Zoom) * *PBMap\TileSize
    CanvasMouseX = GetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_MouseX) - *PBMap\Drawing\RadiusX
    CanvasMouseY = GetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_MouseY) - *PBMap\Drawing\RadiusY
    ; rotation wip
    ; StartVectorDrawing(CanvasVectorOutput(*PBMap\Gadget))
    ; RotateCoordinates(0, 0, *PBMap\Angle)
    ; CanvasMouseX = ConvertCoordinateX(MouseX, MouseY, #PB_Coordinate_Device, #PB_Coordinate_User)
    ; CanvasMouseY = ConvertCoordinateY(MouseX, MouseY, #PB_Coordinate_Device, #PB_Coordinate_User)
    ; StopVectorDrawing()
    Select EventType()
      Case #PB_EventType_Focus
        *PBMap\Drawing\RadiusX = GadgetWidth(*PBMap\Gadget) / 2
        *PBMap\Drawing\RadiusY = GadgetHeight(*PBMap\Gadget) / 2
      Case #PB_EventType_KeyUp  
        Select GetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_Key)
          Case #PB_Shortcut_Delete
            DeleteSelectedMarkers()
            DeleteSelectedTracks()
        EndSelect
        *PBMap\Redraw = #True
        If GetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_Modifiers)&#PB_Canvas_Control = 0
          CtrlKey = #False
        EndIf
      Case #PB_EventType_KeyDown
        With *PBMap\Markers()
          Select GetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_Key)
            Case #PB_Shortcut_Left
              ForEach *PBMap\Markers()
                If \Selected
                  \GeographicCoordinates\Longitude = ClipLongitude( \GeographicCoordinates\Longitude - 10* 360 / Pow(2, *PBMap\Zoom + 8))
                EndIf
              Next            
            Case #PB_Shortcut_Up        
              ForEach *PBMap\Markers()
                If \Selected
                  \GeographicCoordinates\Latitude + 10* 360 / Pow(2, *PBMap\Zoom + 8)
                EndIf
              Next            
            Case #PB_Shortcut_Right     
              ForEach *PBMap\Markers()
                If \Selected
                  \GeographicCoordinates\Longitude = ClipLongitude( \GeographicCoordinates\Longitude + 10* 360 / Pow(2, *PBMap\Zoom + 8))
                EndIf
              Next            
            Case #PB_Shortcut_Down
              ForEach *PBMap\Markers()
                If \Selected
                  \GeographicCoordinates\Latitude - 10* 360 / Pow(2, *PBMap\Zoom + 8)
                EndIf
              Next            
          EndSelect
        EndWith
        *PBMap\Redraw = #True
        If GetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_Modifiers)&#PB_Canvas_Control <> 0
          CtrlKey = #True
        EndIf
      Case #PB_EventType_LeftDoubleClick
        LatLon2Pixel(@*PBMap\GeographicCoordinates, @*PBMap\PixelCoordinates, *PBMap\Zoom)
        MouseX = *PBMap\PixelCoordinates\x  + CanvasMouseX
        MouseY = *PBMap\PixelCoordinates\y  + CanvasMouseY
        ; Clip MouseX to the map range (in X, the map is infinite)
        MouseX = Mod(Mod(MouseX, MapWidth) + MapWidth, MapWidth)
        Touch = #False
        ; Check if the mouse touch a marker
        ForEach *PBMap\Markers()              
          LatLon2Pixel(@*PBMap\Markers()\GeographicCoordinates, @MarkerCoords, *PBMap\Zoom)
          If Distance(MarkerCoords\x, MarkerCoords\y, MouseX, MouseY) < 8
            If *PBMap\Mode = #MODE_DEFAULT Or *PBMap\Mode = #MODE_SELECT
              ; Jump to the marker
              Touch = #True
              SetLocation(*PBMap\Markers()\GeographicCoordinates\Latitude, *PBMap\Markers()\GeographicCoordinates\Longitude)
            ElseIf *PBMap\Mode = #MODE_EDIT
              ; Edit the legend
              MarkerEdit(@*PBMap\Markers())
            EndIf
            Break
          EndIf
        Next
        If Not Touch
          GotoPixel(MouseX, MouseY)
        EndIf
      Case #PB_EventType_MouseWheel
        If *PBMap\Options\WheelMouseRelative
          ; Relative zoom (centered on the mouse)
          SetZoomOnPixel(CanvasMouseX, CanvasMouseY, GetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_WheelDelta))
        Else
          ; Absolute zoom (centered on the center of the map)
          SetZoom(GetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_WheelDelta), #PB_Relative)
        EndIf        
      Case #PB_EventType_LeftButtonDown
        ; LatLon2Pixel(@*PBMap\GeographicCoordinates, @*PBMap\PixelCoordinates, *PBMap\Zoom)
        *PBMap\Dragging = #True
        ; Memorize cursor Coord
        *PBMap\MoveStartingPoint\x = CanvasMouseX
        *PBMap\MoveStartingPoint\y = CanvasMouseY
        ; Clip MouseX to the map range (in X, the map is infinite)
        *PBMap\MoveStartingPoint\x = Mod(Mod(*PBMap\MoveStartingPoint\x, MapWidth) + MapWidth, MapWidth)
        If *PBMap\Mode = #MODE_DEFAULT Or *PBMap\Mode = #MODE_SELECT
          *PBMap\EditMarker = #False
          ; Check if we select marker(s)
          ForEach *PBMap\Markers()                   
            If CtrlKey = #False
              *PBMap\Markers()\Selected = #False ; If no CTRL key, deselect everything and select only the focused marker
            EndIf
            If *PBMap\Markers()\Focus
              *PBMap\Markers()\Selected = #True
              *PBMap\EditMarker = #True; ListIndex(*PBMap\Markers())  
              *PBMap\Markers()\Focus = #False
            EndIf
          Next
          ; Check if we select track(s)
          ForEach *PBMap\TracksList()                   
            If CtrlKey = #False
              *PBMap\TracksList()\Selected = #False ; If no CTRL key, deselect everything and select only the focused track
            EndIf
            If *PBMap\TracksList()\Focus
              *PBMap\TracksList()\Selected = #True
              *PBMap\TracksList()\Focus = #False
            EndIf
          Next
        EndIf
        ; YA pour sélectionner un point de la trace avec le clic gauche
        If *PBMap\EditMarker = #False 
          Location\Latitude = GetMouseLatitude()
          Location\Longitude = GetMouseLongitude()
          If *PBMap\CallBackLeftClic > 0
            CallFunctionFast(*PBMap\CallBackLeftClic, @Location)
          EndIf 
          ; ajout YA // change la forme du pointeur de souris pour les déplacements de la carte
          SetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_Cursor, #PB_Cursor_Hand)
        Else
          SetGadgetAttribute(*PBMap\Gadget, #PB_Canvas_Cursor, #PB_Cursor_Default) ; ajout YA pour remettre le pointeur souris en normal
        EndIf
      Case #PB_EventType_MouseMove
        ; Drag
        If *PBMap\Dragging
          ; If *PBMap\MoveStartingPoint\x <> - 1
          MouseX = CanvasMouseX - *PBMap\MoveStartingPoint\x
          MouseY = CanvasMouseY - *PBMap\MoveStartingPoint\y
          *PBMap\MoveStartingPoint\x = CanvasMouseX
          *PBMap\MoveStartingPoint\y = CanvasMouseY
          ; Move selected markers
          If *PBMap\EditMarker And (*PBMap\Mode = #MODE_DEFAULT Or *PBMap\Mode = #MODE_SELECT)
            ForEach *PBMap\Markers()
              If *PBMap\Markers()\Selected
                LatLon2Pixel(@*PBMap\Markers()\GeographicCoordinates, @MarkerCoords, *PBMap\Zoom)
                MarkerCoords\x + MouseX
                MarkerCoords\y + MouseY
                Pixel2LatLon(@MarkerCoords, @*PBMap\Markers()\GeographicCoordinates, *PBMap\Zoom)
              EndIf
            Next
          ElseIf *PBMap\Mode = #MODE_DEFAULT Or *PBMap\Mode = #MODE_HAND
            ; Move map only
            LatLon2Pixel(@*PBMap\GeographicCoordinates, @*PBMap\PixelCoordinates, *PBMap\Zoom) ; This line could be removed as the coordinates don't have to change but I want to be sure we rely only on geographic coordinates
            *PBMap\PixelCoordinates\x - MouseX
            ; Ensures that pixel position stay in the range [0..2^Zoom**PBMap\TileSize[ coz of the wrapping of the map
            *PBMap\PixelCoordinates\x = Mod(Mod(*PBMap\PixelCoordinates\x, MapWidth) + MapWidth, MapWidth)
            *PBMap\PixelCoordinates\y - MouseY
            Pixel2LatLon(@*PBMap\PixelCoordinates, @*PBMap\GeographicCoordinates, *PBMap\Zoom)
            ; If CallBackLocation send Location to function
            If *PBMap\CallBackLocation > 0
              CallFunctionFast(*PBMap\CallBackLocation, @*PBMap\GeographicCoordinates)
            EndIf 
          EndIf
          *PBMap\Redraw = #True
        Else
          ; Touch test
          LatLon2Pixel(@*PBMap\GeographicCoordinates, @*PBMap\PixelCoordinates, *PBMap\Zoom)
          MouseX = *PBMap\PixelCoordinates\x + CanvasMouseX 
          MouseY = *PBMap\PixelCoordinates\y + CanvasMouseY 
          ; Clip MouseX to the map range (in X, the map is infinite)
          MouseX = Mod(Mod(MouseX, MapWidth) + MapWidth, MapWidth)
          If *PBMap\Mode = #MODE_DEFAULT Or *PBMap\Mode = #MODE_SELECT Or *PBMap\Mode = #MODE_EDIT
            ; Check if mouse touch markers
            ForEach *PBMap\Markers()              
              LatLon2Pixel(@*PBMap\Markers()\GeographicCoordinates, @MarkerCoords, *PBMap\Zoom)
              If Distance(MarkerCoords\x, MarkerCoords\y, MouseX, MouseY) < 8
                *PBMap\Markers()\Focus = #True
                *PBMap\Redraw = #True
              ElseIf *PBMap\Markers()\Focus
                ; If CtrlKey = #False
                *PBMap\Markers()\Focus = #False
                *PBMap\Redraw = #True
              EndIf
            Next
            ; Check if mouse touch tracks           
            If *PBMap\Options\ShowTrackSelection ; YA ajout pour éviter la sélection de la trace
              With *PBMap\TracksList()
                ; Trace Track
                If ListSize(*PBMap\TracksList()) > 0
                  ForEach *PBMap\TracksList()
                    If ListSize(\Track()) > 0
                      If \Visible
                        StartVectorDrawing(CanvasVectorOutput(*PBMap\Gadget))
                        ; Simulates track drawing
                        ForEach \Track()
                          LatLon2Pixel(@*PBMap\TracksList()\Track(),  @Pixel, *PBMap\Zoom)
                          If ListIndex(\Track()) = 0
                            MovePathCursor(Pixel\x, Pixel\y)
                          Else
                            AddPathLine(Pixel\x, Pixel\y)    
                          EndIf
                        Next
                        If IsInsideStroke(MouseX, MouseY, \StrokeWidth)
                          \Focus = #True
                          *PBMap\Redraw = #True
                        ElseIf \Focus
                          \Focus = #False
                          *PBMap\Redraw = #True
                        EndIf
                        StopVectorDrawing()
                      EndIf  
                    EndIf
                  Next
                EndIf
              EndWith
            EndIf
          EndIf
        EndIf
      Case #PB_EventType_LeftButtonUp
        SetGadgetAttribute(*PBMap\Gadget,#PB_Canvas_Cursor,#PB_Cursor_Default) ; ajout YA pour remettre le pointeur souris en normal
                                                                               ; *PBMap\MoveStartingPoint\x = - 1
        *PBMap\Dragging = #False
        *PBMap\Redraw = #True
        ;YA pour connaitre les coordonnées d'un marqueur après déplacement
        ForEach *PBMap\Markers()
          If *PBMap\Markers()\Selected = #True
            If *PBMap\CallBackMarker > 0
              CallFunctionFast(*PBMap\CallBackMarker,  @*PBMap\Markers());
            EndIf 
          EndIf
        Next
      Case #PB_MAP_REDRAW
        *PBMap\Redraw = #True
      Case #PB_MAP_RETRY
        *PBMap\Redraw = #True
        ;- #PB_MAP_TILE_CLEANUP : Tile web loading thread cleanup 
        ; After a Web tile loading thread, clean the tile structure memory, see GetImageThread()
      Case #PB_MAP_TILE_CLEANUP
        *Tile = EventData() 
        key = *Tile\key           
        *Tile\Download = 0
        If FindMapElement(*PBMap\MemCache\Images(), key) <> 0
          ; If the map element has not been deleted during the thread lifetime (should not occur)
          *PBMap\MemCache\Images(key)\Tile = *Tile\Size
          If *Tile\Size
            *PBMap\MemCache\Images(key)\Tile = -1 ; Web loading thread has finished successfully
                                                  ;- Allows to post edit the tile image file with a customised code
            If *PBMap\CallBackModifyTileFile
              TileNewFilename = *PBMap\CallBackModifyTileFile(*Tile\CacheFile, *Tile\URL)
              If TileNewFilename
                ;TODO : Not used by now, a new filename is sent back
                *Tile\CacheFile = TileNewFilename
              EndIf
            EndIf
          Else
            *PBMap\MemCache\Images(key)\Tile = 0
          EndIf
        EndIf
        FreeMemory(*Tile)                                       ; Frees the data needed for the thread (*tile=*PBMap\MemCache\Images(key)\Tile)
        *PBMap\ThreadsNB - 1
        *PBMap\DownloadSlots - 1
        *PBMap\Redraw = #True
    EndSelect
  EndProcedure
  
  ; Redraws at regular intervals
  Procedure TimerEvents()
    Protected *PBMap.PBMap
    ForEach PBMaps()
      *PBMap = PBMaps()
      If EventTimer() = *PBMap\Timer And (*PBMap\Redraw Or *PBMap\Dirty)
        MemoryCacheManagement()
        Drawing()
      EndIf
    Next
  EndProcedure 
  
  ; Could be called directly to attach our map to an existing canvas
  Procedure BindMapGadget(Gadget.i, TimerNB = 1)
    Protected *PBMap.PBMap
    *PBMap.PBMap = AllocateStructure(PBMap)    
    If *PBMap = 0
      FatalError("Cannot initialize PBMap memory")
    EndIf
    PBMaps(Str(Gadget)) = *PBMap
    With *PBMap
      Protected Result.i
      \ZoomMin = 1
      \ZoomMax = 18
      \Dragging = #False
      \TileSize = 256
      \Dirty = #False
      \EditMarker = #False
      \StandardFont = LoadFont(#PB_Any, "Arial", 20, #PB_Font_Bold)
      \UnderlineFont = LoadFont(#PB_Any, "Arial", 20, #PB_Font_Underline)
      \Window = GetActiveWindow()
      \Timer = TimerNB
      \Mode = #MODE_DEFAULT
      \MemoryCacheAccessMutex = CreateMutex() 
      If \MemoryCacheAccessMutex = #False
        MyDebug("Cannot create a mutex", 0)
        End
      EndIf
    EndWith
    LoadOptions(*PBMap)
    TechnicalImagesCreation(*PBMap)
    SetLocation(*PBMap, 0, 0)    
    *PBMap\Gadget = Gadget
    BindGadgetEvent(*PBMap\Gadget, @CanvasEvents())
    AddWindowTimer(*PBMap\Window, *PBMap\Timer, *PBMap\Options\TimerInterval)
    BindEvent(#PB_Event_Timer, @TimerEvents())
    *PBMap\Drawing\RadiusX = GadgetWidth(*PBMap\Gadget) / 2
    *PBMap\Drawing\RadiusY = GadgetHeight(*PBMap\Gadget) / 2
  EndProcedure
  
  ; Creates a canvas and attach our map
  Procedure MapGadget(Gadget.i, X.i, Y.i, Width.i, Height.i, TimerNB = 1)
    If Gadget = #PB_Any
      Protected GadgetNB.i      
      GadgetNB = CanvasGadget(#PB_Any, X, Y, Width, Height, #PB_Canvas_Keyboard)  ; #PB_Canvas_Keyboard has to be set for mousewheel to work on windows
      BindMapGadget(GadgetNB, TimerNB) 
      ProcedureReturn GadgetNB
    Else
      If CanvasGadget(Gadget, X, Y, Width, Height, #PB_Canvas_Keyboard)
        BindMapGadget(Gadget, TimerNB)
      Else
        FatalError("Cannot create the map gadget")
      EndIf
    EndIf  
  EndProcedure
  
  Procedure Quit(*PBMap.PBMap)
    *PBMap\Drawing\End = #True
    ; Wait for loading threads to finish nicely. Passed 2 seconds, kills them.
    Protected TimeCounter = ElapsedMilliseconds()
    Repeat
      ForEach *PBMap\MemCache\Images()
        If *PBMap\MemCache\Images()\Tile > 0
          If IsThread(*PBMap\MemCache\Images()\Tile\GetImageThread)
            If ElapsedMilliseconds() - TimeCounter > 2000
              ; Should not occur
              KillThread(*PBMap\MemCache\Images()\Tile\GetImageThread)
            EndIf
          Else
            FreeMemory(*PBMap\MemCache\Images()\Tile)
            *PBMap\MemCache\Images()\Tile = 0
          EndIf
        Else
          DeleteMapElement(*PBMap\MemCache\Images())
        EndIf
      Next
      Delay(10)
    Until MapSize(*PBMap\MemCache\Images()) = 0
    RemoveWindowTimer(*PBMap\Window, *PBMap\Timer)
    UnbindGadgetEvent(*PBMap\Gadget, @CanvasEvents())
    FreeStructure(*PBMap)
  EndProcedure
  
  Procedure FreeMapGadget(Gadget.i)
    Protected *PBMap.PBMap
    ForEach PBMaps()
      *PBMap = PBMaps()
      If *PBMap\Gadget = Gadget
        Quit(*PBMap)
        DeleteMapElement(PBMaps())
      EndIf
    Next
  EndProcedure
  
  Procedure SelectPBMap(Gadget.i)                   ; Could be used to have multiple PBMaps in one window
    *PBMap = PBMaps(Str(Gadget))
  EndProcedure

EndModule

; ****************************************************************
; 
;- Example of application
; 
; ****************************************************************

CompilerIf #PB_Compiler_IsMainFile 
  InitNetwork()
  
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
    PBMap::Refresh()
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
    PBMap::SetOption("ShowDegrees", "1") : Degrees = 0
    PBMap::SetOption("ShowDebugInfos", "1")
    PBMap::SetDebugLevel(5)
    PBMap::SetOption("Verbose", "0")
    PBMap::SetOption("ShowScale", "1")    
    PBMap::SetOption("Warning", "1")
    PBMap::SetOption("ShowMarkersLegend", "1")
    PBMap::SetOption("ShowTrackKms", "1")
    PBMap::SetOption("ColourFocus", "$FFFF00AA") 

    PBMap::SetCallBackMainPointer(@MainPointer())                   ; To change the main pointer (center of the view)
    PBMap::SetCallBackLocation(@UpdateLocation())                   ; To obtain realtime coordinates
    PBMap::SetLocation(-36.81148, 175.08634,12)                     ; Change the PBMap coordinates
    PBMap::SetMapScaleUnit(PBMAP::#SCALE_KM)                        ; To change the scale unit
    PBMap::AddMarker(49.0446828398, 2.0349812508, "", "", -1, @MyMarker())  ; To add a marker with a customised GFX
    PBMap::SetCallBackMarker(@MarkerMoveCallBack())
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
              PBMap::SetLocation(10* 360 / Pow(2, PBMap::GetZoom() + 8), 0, 0, #PB_Relative)
            Case #Gdt_Down
              PBMap::SetLocation(10* -360 / Pow(2, PBMap::GetZoom() + 8), 0, 0, #PB_Relative)
            Case #Gdt_Left
              PBMap::SetLocation(0, 10* -360 / Pow(2, PBMap::GetZoom() + 8), 0, #PB_Relative)
            Case #Gdt_Right
              PBMap::SetLocation(0, 10* 360 / Pow(2, PBMap::GetZoom() + 8), 0, #PB_Relative)
              ; Case #Gdt_RotateLeft
              ; PBMAP::SetAngle(-5,#PB_Relative) 
              ; PBMap::Refresh()
              ; Case #Gdt_RotateRight
              ; PBMAP::SetAngle(5,#PB_Relative) 
              ; PBMap::Refresh()
            Case #Button_4
              PBMap::SetZoom(1)
            Case #Button_5
              PBMap::SetZoom( - 1)
            Case #Gdt_LoadGpx
              *Track = PBMap::LoadGpxFile(OpenFileRequester("Choose a file to load", "", "Gpx|*.gpx", 0))
              PBMap::SetTrackColour(*Track, RGBA(Random(255), Random(255), Random(255), 128))
            Case #Gdt_SaveGpx
              If *Track
                If PBMap::SaveGpxFile(SaveFileRequester("Choose a filename", "mytrack.gpx", "Gpx|*.gpx", 0), *Track)
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
              PBMap::AddMarker(ValD(GetGadgetText(#StringLatitude)), ValD(GetGadgetText(#StringLongitude)), "", "Test", RGBA(Random(255), Random(255), Random(255), 255))
            Case #Gdt_AddOpenseaMap
              If PBMap::IsLayer("OpenSeaMap")
                PBMap::DeleteLayer("OpenSeaMap")
                SetGadgetState(#Gdt_AddOpenseaMap, 0)
              Else
                PBMap::AddOSMServerLayer("OpenSeaMap", 3, "http://t1.openseamap.org/seamark/") ; Add a special osm overlay map on layer nb 3
                SetGadgetState(#Gdt_AddOpenseaMap, 1)
              EndIf
              PBMap::Refresh()
            Case #Gdt_AddHereMap
              If PBMap::IsLayer("Here")
                PBMap::DeleteLayer("Here")
                SetGadgetState(#Gdt_AddHereMap, 0)
              Else
                If PBMap::GetOption("appid") <> "" And PBMap::GetOption("appcode") <> ""
                  PBMap::AddHereServerLayer("Here", 2) ; Add a "HERE" overlay map on layer nb 2
                  PBMap::SetLayerAlpha("Here", 0.75)
                Else
                  MessageRequester("Info", "Don't forget to register on HERE and change the following line or edit options file")
                  PBMap::AddHereServerLayer("Here", 2, "my_id", "my_code") ; Add a here overlay map on layer nb 2
                EndIf
                SetGadgetState(#Gdt_AddHereMap, 1)
              EndIf
              PBMap::Refresh()
            Case #Gdt_AddGeoServerMap
              If PBMap::IsLayer("GeoServer")
                PBMap::DeleteLayer("GeoServer")
                SetGadgetState(#Gdt_AddGeoServerMap, 0)
              Else
                PBMap::AddGeoServerLayer("GeoServer", 3, "demolayer", "http://localhost:8080/", "geowebcache/service/gmaps", "image/png") ; Add a geoserver overlay map on layer nb 3
                PBMap::SetLayerAlpha("GeoServer", 0.75)
                SetGadgetState(#Gdt_AddGeoServerMap, 1)
              EndIf
              PBMap::Refresh()
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
            Case #Gdt_ClearDiskCache
              PBMap::ClearDiskCache()
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
                PBMap::NominatimGeoLocationQuery(GetGadgetText(#StringGeoLocationQuery))
                PBMap::Refresh()
              EndIf
              ; *** TODO : code to change when the SetActiveGadget(-1) will be fixed
              SetActiveGadget(Dummy)
              ; ***
            Case  #MenuEventLonLatStringEnter
              PBMap::SetLocation(ValD(GetGadgetText(#StringLatitude)), ValD(GetGadgetText(#StringLongitude)))                     ; Change the PBMap coordinates
              PBMap::Refresh()
          EndSelect
      EndSelect
    Until Quit = #True
    
    PBMap::FreeMapGadget(#Map)
  EndIf
  
CompilerEndIf


; IDE Options = PureBasic 5.61 (Windows - x64)
; CursorPosition = 897
; FirstLine = 895
; Folding = ---------------------
; EnableThread
; EnableXP
; CompileSourceDirectory