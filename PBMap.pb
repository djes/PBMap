;************************************************************** 
; Program:           PBMap
; Description:       Permits the use of tiled maps like 
;                    OpenStreetMap in a handy PureBASIC module
; Author:            Thyphoon And Djes
; Date:              Mai 17, 2016
; License:           Free, unrestricted, credit appreciated 
;                    but not required.
; Note:              Please share improvement !
; Thanks:            Progi1984
; Usage:             Change the Proxy global variables if needed
;                    (see also Proxy Details)
;************************************************************** 

#Red = 255

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
  Global MyDebugLevel = 3
  ;-Proxy ON/OFF  
  Global Proxy = #False
  Declare InitPBMap(window)
  Declare SetMapServer(ServerURL.s = "http://tile.openstreetmap.org/", TileSize = 256, ZoomMin = 0, ZoomMax = 18)
  Declare MapGadget(Gadget.i, X.i, Y.i, Width.i, Height.i)
  Declare Event(Event.l)
  Declare SetLocation(latitude.d, longitude.d, zoom = 15, mode.i = #PB_Absolute)
  Declare Drawing()
  Declare SetZoom(Zoom.i, mode.i = #PB_Relative)
  Declare ZoomToArea()
  Declare SetCallBackLocation(*CallBackLocation)
  Declare SetCallBackMainPointer(CallBackMainPointer.i)
  Declare LoadGpxFile(file.s);  
  Declare AddMarker(Latitude.d,Longitude.d,color.l=-1, CallBackPointer.i = -1)
  Declare Quit()
  Declare Error(msg.s)
  Declare Refresh()
  Declare.d GetLatitude()
  Declare.d GetLongitude()
  Declare.i GetZoom()
EndDeclareModule

Module PBMap 
  
  EnableExplicit
  
  Structure Location
    Longitude.d
    Latitude.d
  EndStructure
  
  Structure Position
    x.d
    y.d
  EndStructure
  
  Structure PixelPosition
    x.i
    y.i
  EndStructure
  
  ;- Tile Structure
  Structure Tile
    Position.Position
    PBMapTileX.i
    PBMapTileY.i
    PBMapZoom.i
    nImage.i
    key.s
    CacheFile.s
    GetImageThread.i
  EndStructure
  
  Structure DrawingParameters
    Position.Position
    Canvas.i
    PBMapTileX.i
    PBMapTileY.i
    PBMapZoom.i
    TargetLocation.Location
    CenterX.i
    CenterY.i
    DeltaX.i
    DeltaY.i
    Dirty.i
    PassNB.i
    End.i
  EndStructure  
  
  Structure TileThread
    *Tile.Tile    
    GetImageThread.i
  EndStructure
  
  Structure ImgMemCach
    nImage.i
    ;Location.Location
    ;Mutex.i
  EndStructure
  
  Structure TileMemCach
    Map Images.ImgMemCach()
  EndStructure
  
  Structure Marker
    Location.Location                       ; Marker latitude and longitude
    color.l                                 ; Marker color
    CallBackPointer.i                       ; @Procedure(X.i, Y.i) to DrawPointer (you must use VectorDrawing lib)
  EndStructure
  
  Structure Option
    WheelMouseRelative.i
  EndStructure
  
  ;-PBMap Structure
  Structure PBMap
    Window.i                                ; Parent Window
    Gadget.i                                ; Canvas Gadget Id 
    Font.i                                  ; Font to uses when write on the map 
    TargetLocation.Location                 ; Latitude and Longitude from focus point
    Drawing.DrawingParameters               ; Drawing parameters based on focus point
    ;
    CallBackLocation.i                      ; @Procedure(latitude.d,lontitude.d)
    CallBackMainPointer.i                   ; @Procedure(X.i, Y.i) to DrawPointer (you must use VectorDrawing lib)
    ;
    Position.PixelPosition                  ; Actual focus point coords in pixels (global)
    MoveStartingPoint.PixelPosition         ; Start mouse position coords when dragging the map
    ;
    ServerURL.s                             ; Web URL ex: http://tile.openstreetmap.org/
    ZoomMin.i                               ; Min Zoom supported by server
    ZoomMax.i                               ; Max Zoom supported by server
    Zoom.i                                  ; Current zoom
    TileSize.i                              ; Tile size downloaded on the server ex : 256
    ;
    HDDCachePath.S                          ; Path where to load and save tiles downloaded from server
    MemCache.TileMemCach                    ; Images in memory cache
    ;
    Moving.i
    Dirty.i                                 ; To signal that drawing need a refresh
    ;
    MainDrawingThread.i
    List TilesThreads.TileThread()
    TileThreadMutex.i;                      ;Mutex to protect resources  
    List track.Location()                   ; To display a GPX track
    List Marker.Marker()                    ; To diplay marker
    EditMarkerIndex.l
    
    ImgLoading.i                            ;Image Loading Tile
    
    Options.option                          ;    
  EndStructure
  
  #PB_MAP_REDRAW = #PB_EventType_FirstCustomValue + 1 
  
  ;-Global variables
  Global PBMap.PBMap, Null.i
  
  ;Shows an error msg and terminates the program
  Procedure Error(msg.s)
    MessageRequester("MapGadget", msg, #PB_MessageRequester_Ok)
    End
  EndProcedure
  
  ;Send debug infos to stdout (allowing mixed debug infos with curl or other libs)
  Procedure MyDebug(msg.s, DbgLevel = 0)
    If Verbose And MyDebugLevel >= DbgLevel
      PrintN(msg)
      ;Debug msg  
    EndIf
  EndProcedure
  
  ;- *** CURL specific ***
  ; (program has To be compiled in console format for curl debug infos)
  
  IncludeFile "libcurl.pbi" ; https://github.com/deseven/pbsamples/tree/master/crossplatform/libcurl
  
  ;Curl write callback (needed for win32 dll)
  ProcedureC ReceiveHTTPWriteToFileFunction(*ptr, Size.i, NMemB.i, FileHandle.i)
    ProcedureReturn WriteData(FileHandle, *ptr, Size * NMemB)    
  EndProcedure
  
  Procedure.i CurlReceiveHTTPToFile(URL$, DestFileName$, ProxyURL$="", ProxyPort$="", ProxyUser$="", ProxyPassword$="")
    Protected *Buffer, curl.i, Timeout.i, res.i
    Protected FileHandle.i
    MyDebug("ReceiveHTTPToFile from " + URL$ + " " + ProxyURL$ + ProxyPort$ + ProxyUser$, 3)
    MyDebug(" to file : " + DestFileName$, 3)
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
        curl_easy_setopt(curl, #CURLOPT_VERBOSE, 1)
        ;curl_easy_setopt(curl, #CURLOPT_CONNECTTIMEOUT, 60)
        If Len(ProxyURL$)
          ;curl_easy_setopt(curl, #CURLOPT_HTTPPROXYTUNNEL, #True)
          If Len(ProxyPort$)
            ProxyURL$ + ":" + ProxyPort$
          EndIf
          MyDebug( ProxyURL$)
          curl_easy_setopt(curl, #CURLOPT_PROXY, str2curl(ProxyURL$))
          If Len(ProxyUser$)
            If Len(ProxyPassword$)
              ProxyUser$ + ":" + ProxyPassword$
            EndIf
            MyDebug( ProxyUser$)
            curl_easy_setopt(curl, #CURLOPT_PROXYUSERPWD, str2curl(ProxyUser$))
          EndIf
        EndIf
        curl_easy_setopt(curl, #CURLOPT_WRITEDATA, FileHandle)
        curl_easy_setopt(curl, #CURLOPT_WRITEFUNCTION, @ReceiveHTTPWriteToFileFunction())
        res = curl_easy_perform(curl)
        If res <> #CURLE_OK
          MyDebug("CURL problem", 3)
        EndIf
        curl_easy_cleanup(curl)
      Else
        MyDebug("Can't init CURL", 3)
      EndIf
      CloseFile(FileHandle)
      ProcedureReturn FileSize(DestFileName$)
    EndIf
    ProcedureReturn #False
  EndProcedure
  ;- ***
  
  Procedure LoadingImageCreation()
    Protected Text$ = "Loading"
    PBmap\ImgLoading = CreateImage(#PB_Any, 256, 256) 
    If  PBmap\ImgLoading
      StartVectorDrawing(ImageVectorOutput(PBMap\Imgloading)) 
      BeginVectorLayer()
      VectorSourceColor(RGBA(255, 255, 255, 128))
      AddPathBox(0, 0, 256, 256)
      FillPath()
      MovePathCursor(0, 0)
      VectorFont(FontID(PBMap\Font), 256 / 20)
      VectorSourceColor(RGBA(150, 150, 150, 255))
      MovePathCursor(0 + (256 - VectorTextWidth(Text$)) / 2, 0 + (256 - VectorTextHeight(Text$)) / 2)
      DrawVectorText(Text$)
      EndVectorLayer()
      StopVectorDrawing() 
    EndIf
  EndProcedure  
  
  Procedure InitPBMap(window)
    Protected Result.i
    If Verbose
      OpenConsole()
    EndIf
    PBMap\HDDCachePath = GetTemporaryDirectory()
    PBMap\ServerURL = "http://tile.openstreetmap.org/"
    PBMap\ZoomMin = 0
    PBMap\ZoomMax = 18
    PBMap\MoveStartingPoint\x = - 1
    PBMap\TileSize = 256
    PBMap\Dirty = #False
    PBMap\TileThreadMutex = CreateMutex()
    PBMap\EditMarkerIndex = -1                      ;Initialised with "no marker selected"
    PBMap\Font = LoadFont(#PB_Any, "Arial", 20, #PB_Font_Bold)
    PBMap\Window = window
    PBMap\Options\WheelMouseRelative = #True
    ;-Preferences
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
    OpenPreferences(GetHomeDirectory() + "PBMap.prefs")
    PreferenceGroup("PROXY")       
    Proxy = ReadPreferenceInteger("Proxy", #False)
    If Proxy
      Global ProxyURL$  = ReadPreferenceString("ProxyURL", "")  ;InputRequester("ProxyServer", "Do you use a Proxy Server? Then enter the full url:", "")
      Global ProxyPort$ = ReadPreferenceString("ProxyPort", "") ;InputRequester("ProxyPort"  , "Do you use a specific port? Then enter it", "")
      Global ProxyUser$ = ReadPreferenceString("ProxyUser", "") ;InputRequester("ProxyUser"  , "Do you use a user name? Then enter it", "")
      Global ProxyPassword$ = InputRequester("ProxyPass", "Do you use a password ? Then enter it", "") ;TODO
    EndIf
    ClosePreferences()
    curl_global_init(#CURL_GLOBAL_WIN32)
    LoadingImageCreation()
  EndProcedure
  
  Procedure SetMapServer(ServerURL.s = "http://tile.openstreetmap.org/", TileSize = 256, ZoomMin = 0, ZoomMax = 18)
    PBMap\ServerURL = ServerURL
    PBMap\ZoomMin = ZoomMin
    PBMap\ZoomMax = ZoomMax
    PBMap\TileSize = TileSize
  EndProcedure
  
  Procedure Quit()
    PBMap\Drawing\End = #True
    ;Wait for loading threads to finish nicely. Passed 2 seconds, kills them.
    Protected TimeCounter = ElapsedMilliseconds()
    Repeat
      ResetList(PBMap\TilesThreads()) 
      While NextElement(PBMap\TilesThreads())
        If IsThread(PBMap\TilesThreads()\GetImageThread) = 0
          FreeMemory(PBMap\TilesThreads()\Tile)
          DeleteElement(PBMap\TilesThreads())
        ElseIf ElapsedMilliseconds() - TimeCounter > 2000
          ;Should not occur
          KillThread(PBMap\TilesThreads()\GetImageThread)
        EndIf
      Wend
      Delay(10)
    Until ListSize(PBMap\TilesThreads()) = 0 
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
  
  Procedure MapGadget(Gadget.i, X.i, Y.i, Width.i, Height.i)
    If Gadget = #PB_Any
      PBMap\Gadget = CanvasGadget(PBMap\Gadget, X, Y, Width, Height, #PB_Canvas_Keyboard) ;#PB_Canvas_Keyboard has to be set for mousewheel to work on windows
    Else
      PBMap\Gadget = Gadget
      CanvasGadget(PBMap\Gadget, X, Y, Width, Height, #PB_Canvas_Keyboard) 
    EndIf 
  EndProcedure
  
  ;*** Converts coords to tile.decimal
  ;Warning, structures used in parameters are not tested
  Procedure LatLon2XY(*Location.Location, *Coords.Position)
    Protected n.d = Pow(2.0, PBMap\Zoom)
    Protected LatRad.d = Radian(*Location\Latitude)
    *Coords\x = n * ( (*Location\Longitude + 180.0) / 360.0)
    *Coords\y = n * ( 1.0 - Log(Tan(LatRad) + 1.0/Cos(LatRad)) / #PI ) / 2.0
    MyDebug("Latitude : " + StrD(*Location\Latitude) + " ; Longitude : " + StrD(*Location\Longitude))
    MyDebug("Coords X : " + Str(*Coords\x) + " ;  Y : " + Str(*Coords\y))
  EndProcedure
  
  ;*** Converts tile.decimal to coords
  ;Warning, structures used in parameters are not tested
  Procedure XY2LatLon(*Coords.Position, *Location.Location)
    Protected n.d = Pow(2.0, PBMap\Zoom)
    Protected LatitudeRad.d
    *Location\Longitude  = *Coords\x / n * 360.0 - 180.0
    LatitudeRad = ATan(SinH(#PI * (1.0 - 2.0 * *Coords\y / n)))
    *Location\Latitude = Degree(LatitudeRad)
  EndProcedure
  
  ; HaversineAlgorithm 
  ; http://andrew.hedges.name/experiments/haversine/
  Procedure.d HaversineInKM(*posA.Location, *posB.Location)
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
  
  Procedure.d HaversineInM(*posA.Location, *posB.Location)
    ProcedureReturn (1000 * HaversineInKM(@*posA,@*posB));
  EndProcedure
  
  Procedure GetPixelCoordFromLocation(*Location.Location, *Pixel.PixelPosition) ; TODO to Optimize 
    Protected mapWidth.l    = Pow(2, PBMap\Zoom + 8)
    Protected mapHeight.l   = Pow(2, PBMap\Zoom + 8)
    Protected x1.l,y1.l
    ; get x value
    x1 = (*Location\Longitude+180)*(mapWidth/360)
    ; convert from degrees To radians
    Protected latRad.d = *Location\Latitude*#PI/180;
    Protected mercN.d = Log(Tan((#PI/4)+(latRad/2)));
    y1     = (mapHeight/2)-(mapWidth*mercN/(2*#PI)) ;
    Protected x2.l, y2.l
    ; get x value
    x2 = (PBMap\TargetLocation\Longitude+180)*(mapWidth/360)
    ; convert from degrees To radians
    latRad = PBMap\TargetLocation\Latitude*#PI/180;
    ; get y value
    mercN = Log(Tan((#PI/4)+(latRad/2)))        
    y2     = (mapHeight/2)-(mapWidth*mercN/(2*#PI));    
    *Pixel\x=GadgetWidth(PBMap\Gadget)/2  - (x2-x1)
    *Pixel\y=GadgetHeight(PBMap\Gadget)/2 - (y2-y1)
  EndProcedure
  
  Procedure LoadGpxFile(file.s)
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
      ClearList(PBMap\track())
      For child = 1 To XMLChildCount(*MainNode)
        *child = ChildXMLNode(*MainNode, child)
        AddElement(PBMap\track())
        If ExamineXMLAttributes(*child)
          While NextXMLAttribute(*child)
            Select XMLAttributeName(*child)
              Case "lat"
                PBMap\track()\Latitude=ValD(XMLAttributeValue(*child))
              Case "lon"
                PBMap\track()\Longitude=ValD(XMLAttributeValue(*child))
            EndSelect
          Wend
        EndIf
      Next 
    EndIf
  EndProcedure
  
  Procedure.i GetTileFromHDD(CacheFile.s)
    Protected nImage.i
    Debug  "Loading image " + CacheFile + " ; Size : " + Str(FileSize(CacheFile))     
    If FileSize(CacheFile) > 0
      nImage = LoadImage(#PB_Any, CacheFile)
      If IsImage(nImage)
        Debug "Success loading " + CacheFile + " as nImage " + Str(nImage)
        MyDebug("Success loading " + CacheFile + " as nImage " + Str(nImage), 3)
        ProcedureReturn nImage  
      Else
        Debug "Failed loading " + CacheFile + " as nImage " + Str(nImage) + " -> not an image !"
        MyDebug("Failed loading " + CacheFile + " as nImage " + Str(nImage) + " -> not an image !", 3)
      EndIf
    Else
      Debug "Failed loading " + CacheFile + " -> Size <= 0"
      MyDebug("Failed loading " + CacheFile + " -> Size <= 0", 3)
    EndIf
    ProcedureReturn -1
  EndProcedure
  
  Procedure.i GetLocalTile(key.s, CacheFile.s)
    MyDebug("Check if we have this image in memory", 3)
    If FindMapElement(PBMap\MemCache\Images(), key)
      MyDebug("Key : " + key + " found !", 3)
      ProcedureReturn PBMap\MemCache\Images()\nImage
    Else
      MyDebug("Key : " + key + " Try HDD!")
      ProcedureReturn GetTileFromHDD(CacheFile.s)
    EndIf
  EndProcedure

  Procedure.i GetTileFromWeb(Zoom.i, XTile.i, YTile.i, CacheFile.s)
    Protected *Buffer
    Protected nImage.i = -1
    Protected FileHandle.i
    Protected TileURL.s = PBMap\ServerURL + Str(Zoom) + "/" + Str(XTile) + "/" + Str(YTile) + ".png"   
    MyDebug("Check if we have this image on Web", 3)
    If Proxy
      FileHandle = CurlReceiveHTTPToFile(TileURL, CacheFile, ProxyURL$, ProxyPort$, ProxyUser$, ProxyPassword$)
      If FileHandle
        nImage = GetTileFromHDD(CacheFile)
      Else
        MyDebug("File " + TileURL + " not correctly received with Curl and proxy", 3)
      EndIf
    Else
      *Buffer = ReceiveHTTPMemory(TileURL)  ;TODO to thread by using #PB_HTTP_Asynchronous
      If *Buffer
        nImage = CatchImage(#PB_Any, *Buffer, MemorySize(*Buffer))
        If IsImage(nImage)
          MyDebug("Load from web " + TileURL + " as Tile nb " + nImage, 3)
          Debug "url: " + TileURL 
          Debug "cache file: " + CacheFile 
          SaveImage(nImage, CacheFile, #PB_ImagePlugin_PNG)
          FreeMemory(*Buffer)
        Else
          MyDebug("Can't catch image " + TileURL, 3)
          nImage = -1
          ;ShowMemoryViewer(*Buffer, MemorySize(*Buffer))
        EndIf
      Else
        Debug("ReceiveHTTPMemory's buffer is empty")
        MyDebug("ReceiveHTTPMemory's buffer is empty", 3)
      EndIf
    EndIf
    ProcedureReturn nImage
  EndProcedure
  
  Procedure GetImageThread(*Tile.Tile)
    Protected nImage.i = -1
    nImage = GetTileFromWeb(*Tile\PBMapZoom, *Tile\PBMapTileX, *Tile\PBMapTileY, *Tile\CacheFile)
    If nImage <> -1
      LockMutex(PBMap\TileThreadMutex)
      PBMap\MemCache\Images(*Tile\key)\nImage = nImage
      UnlockMutex(PBMap\TileThreadMutex)
      MyDebug("Image nb " + Str(nImage) + " successfully added to mem cache")   
      MyDebug("With the following key : " + *Tile\key)  
    Else
      MyDebug("Error GetImageThread procedure, image not loaded - " + *Tile\key)
      nImage = -1
    EndIf
    ;Define this tile image nb
    *Tile\nImage = nImage
    PostEvent(#PB_Event_Gadget, PBMap\window,PBmap\Gadget, #PB_MAP_REDRAW, *Tile)
  EndProcedure
  
  Procedure DrawTile(*Tile.Tile)
    Protected x = *Tile\Position\x 
    Protected y = *Tile\Position\y 
    MyDebug("  Drawing tile nb " + " X : " + Str(*Tile\PBMapTileX) + " Y : " + Str(*Tile\PBMapTileX), 2)
    MyDebug("  at coords " + Str(x) + "," + Str(y), 2)
    MovePathCursor(x, y)
    DrawVectorImage(ImageID(*Tile\nImage))
  EndProcedure
  
  Procedure DrawLoading(*Tile.Tile)
    Protected x = *Tile\Position\x 
    Protected y = *Tile\Position\y 
    Protected Text$ = "Loading"
    MyDebug("  Drawing tile nb " + " X : " + Str(*Tile\PBMapTileX) + " Y : " + Str(*Tile\PBMapTileX), 2)
    MyDebug("  at coords " + Str(x) + "," + Str(y))
  EndProcedure
  
  Procedure DrawTiles(*Drawing.DrawingParameters)
    ;DisableDebugger
    Protected x.i, y.i
    Protected tx = Int(*Drawing\Position\x)  ;Don't forget the Int() !
    Protected ty = Int(*Drawing\Position\y)
    Protected nx = *Drawing\CenterX / PBMap\TileSize ;How many tiles around the point
    Protected ny = *Drawing\CenterY / PBMap\TileSize
    Protected px, py, img, key.s, CacheFile.s
    MyDebug("Drawing tiles")
    For y = - ny - 1 To ny + 1
      For x = - nx - 1 To nx + 1
         px = *Drawing\CenterX + x * PBMap\TileSize - *Drawing\DeltaX
         py = *Drawing\CenterY + y * PBMap\TileSize - *Drawing\DeltaY
         CacheFile = PBMap\HDDCachePath + "PBMap_" + Str(PBMap\Zoom) + "_" + Str(tx + x) + "_" + Str(ty + y) + ".png"
         key = "Z" + RSet(Str(PBMap\Zoom), 4, "0") + "X" + RSet(Str(tx + x), 8, "0") + "Y" + RSet(Str(ty + y), 8, "0")  ;Unique identifier
         img = GetLocalTile(key, CacheFile)
         If img <> -1  
           MovePathCursor(px, py)
           DrawVectorImage(ImageID(img))
         Else 
           MovePathCursor(px, py)
           DrawVectorImage(ImageID(PBMap\ImgLoading))
           Protected *NewTile.Tile = AllocateMemory(SizeOf(Tile))
           If *NewTile
             With *NewTile
               ;Keep a track of tiles (especially to free memory)
               AddElement(PBMap\TilesThreads())
               PBMap\TilesThreads()\Tile = *NewTile
               ;New tile parameters
               \Position\x = px ;*Drawing\CenterX + x * PBMap\TileSize - *Drawing\DeltaX
               \Position\y = py ;*Drawing\CenterY + y * PBMap\TileSize - *Drawing\DeltaY
               \PBMapTileX = tx + x
               \PBMapTileY = ty + y
               \PBMapZoom  = PBMap\Zoom
               \key = key
               \CacheFile = CacheFile
               LockMutex(PBMap\TileThreadMutex)
               AddMapElement(PBMap\MemCache\Images(), \key) ;Add the image to the cache, once in this loop
               PBMap\MemCache\Images()\nImage = PBMap\ImgLoading
               UnlockMutex(PBMap\TileThreadMutex)
               \GetImageThread = CreateThread(@GetImageThread(), *NewTile)
               PBMap\TilesThreads()\GetImageThread = \GetImageThread
               myDebug(" Creating get image thread nb " + Str(\GetImageThread))
             EndWith  
           Else
             MyDebug(" Error, can't create a new tile")
             Break 2
           EndIf   
         EndIf 
       Next
     Next
            ;Free tile memory
    ;TODO : maybe get out this proc from drawtiles in a special "free ressources" task
    ForEach PBMap\TilesThreads()
      ;Check if there's no more loading thread
      If IsThread(PBMap\TilesThreads()\GetImageThread) = 0
        FreeMemory(PBMap\TilesThreads()\Tile)
        DeleteElement(PBMap\TilesThreads())
      EndIf         
    Next
    ;EnableDebugger 
  EndProcedure
  
;     ;-**** Clean Mem Cache
;     ;TODO in development, by now there's many cache problem as the loading thread could be perturbed
;     ;GadgetWidth(PBMap\Gadget)/PBMap\TileSize
;     Protected MaxNbTile.l
;     If GadgetWidth(PBMap\Gadget)>GadgetHeight(PBMap\Gadget)
;       MaxNbTile=GadgetWidth(PBMap\Gadget)/PBMap\TileSize
;     Else
;       MaxNbTile=GadgetHeight(PBMap\Gadget)/PBMap\TileSize
;     EndIf
;     Protected Scale.d= 40075*Cos(Radian(PBMap\TargetLocation\Latitude))/Pow(2,PBMap\Zoom)
;     Protected Limit.d=Scale*(MaxNbTile)*1.5
;     Debug "Cache cleaning"
;     ForEach PBMap\MemCache\Images()
;         Protected Distance.d = HaversineInKM(@PBMap\MemCache\Images()\Location, @PBMap\TargetLocation)
;         Debug "Limit:"+StrD(Limit)+" Distance:"+StrD(Distance)
;         If Distance>Limit And IsImage(PBMap\MemCache\Images()\nImage) 
;           LockMutex(PBMap\MemCache\Images()\Mutex)          
;           Debug "delete"
;           Debug PBMap\MemCache\Images()
;           FreeImage(PBMap\MemCache\Images()\nImage)
;           UnlockMutex(PBMap\MemCache\Images()\Mutex)
;           FreeMutex(PBMap\MemCache\Images()\Mutex)
;           DeleteMapElement(PBMap\MemCache\Images())
;         EndIf
;     Next
  
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
      ;FillPath(#PB_Path_Preserve) 
      ;ClipPath(#PB_Path_Preserve)
      AddPathCircle(0, -16, 5, 0, 360, #PB_Path_Relative)
      VectorSourceColor(RGBA($FF, 0, 0, $FF))
      FillPath(#PB_Path_Preserve):VectorSourceColor(RGBA($FF, 0, 0, $FF));RGBA(0, 0, 0, 255)) 
      StrokePath(1)
    EndIf  
  EndProcedure
  
  Procedure DrawScale(*Drawing.DrawingParameters)
    ;TODO Add Option and function to display Scale on Map
    Protected Scale.d= 40075*Cos(Radian(PBMap\TargetLocation\Latitude))/Pow(2,PBMap\Zoom)
    VectorFont(FontID(PBMap\Font), 30)
    VectorSourceColor(RGBA(0, 0, 0, 80))
    MovePathCursor(50,50)
    DrawVectorText(StrD(Scale))
  EndProcedure
        
  Procedure TrackPointer(x.i, y.i,dist.l)
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
  
  Procedure  DrawTrack(*Drawing.DrawingParameters)
    Protected Pixel.PixelPosition
    Protected Location.Location
    Protected km.f, memKm.i
    If ListSize(PBMap\track())>0
      ;Trace Track
      ForEach PBMap\track()
        If *Drawing\TargetLocation\Latitude<>0 And  *Drawing\TargetLocation\Longitude<>0
          GetPixelCoordFromLocation(@PBMap\track(),@Pixel)
          If ListIndex(PBMap\track())=0
            MovePathCursor(Pixel\X, Pixel\Y)
          Else
            AddPathLine(Pixel\X, Pixel\Y)    
          EndIf 
        EndIf 
      Next
      VectorSourceColor(RGBA(0, 255, 0, 150))
      StrokePath(10, #PB_Path_RoundEnd|#PB_Path_RoundCorner)
      ;Draw Distance
      ForEach PBMap\track()
        ;-Test Distance
        If ListIndex(PBMap\track())=0
          Location\Latitude=PBMap\track()\Latitude
          Location\Longitude=PBMap\track()\Longitude 
        Else 
          km=km+HaversineInKM(@Location,@PBMap\track()) ;<- display Distance 
          Location\Latitude=PBMap\track()\Latitude
          Location\Longitude=PBMap\track()\Longitude 
        EndIf 
        GetPixelCoordFromLocation(@PBMap\track(),@Pixel)
        If Int(km)<>memKm
          memKm=Int(km)
          If PBMap\Zoom>10
            BeginVectorLayer()
            TrackPointer(Pixel\X , Pixel\Y,Int(km))
            EndVectorLayer()
          EndIf 
        EndIf
      Next
    EndIf
  EndProcedure
  
  ; Add a Marker To the Map
  Procedure AddMarker(Latitude.d,Longitude.d,color.l=-1, CallBackPointer.i = -1)
    AddElement(PBMap\Marker())
    PBMap\Marker()\Location\Latitude=Latitude
    PBMap\Marker()\Location\Longitude=Longitude
    PBMap\Marker()\color=color
    PBMap\Marker()\CallBackPointer = CallBackPointer
  EndProcedure
  
  ; Draw all markers on the screen !
  Procedure  DrawMarker(*Drawing.DrawingParameters)
    Protected Pixel.PixelPosition
    ForEach PBMap\Marker()
      If PBMap\Marker()\Location\Latitude <> 0 And PBMap\Marker()\Location\Longitude <> 0
        GetPixelCoordFromLocation(PBMap\Marker()\Location, @Pixel)
        If Pixel\X >= 0 And Pixel\Y >= 0 And Pixel\X < GadgetWidth(PBMap\Gadget) And Pixel\Y < GadgetHeight(PBMap\Gadget) ; Only if visible ^_^
          If PBMap\Marker()\CallBackPointer > 0
            CallFunctionFast(PBMap\Marker()\CallBackPointer, Pixel\X, Pixel\Y)
          Else
            DrawPointer(*Drawing)
          EndIf
        EndIf 
      EndIf 
    Next
  EndProcedure
  
  ;-*** Main drawing
  Procedure Drawing()
    Protected *Drawing.DrawingParameters = @PBMap\Drawing
    Protected Px.d, Py.d
    ;Precalc some values
    *Drawing\CenterX = GadgetWidth(PBMap\Gadget) / 2
    *Drawing\CenterY = GadgetHeight(PBMap\Gadget) / 2
    ;Pixel shift, aka position in the tile
    Px = *Drawing\Position\x : Py = *Drawing\Position\y
    *Drawing\DeltaX = Px * PBMap\TileSize - (Int(Px) * PBMap\TileSize) ;Don't forget the Int() !
    *Drawing\DeltaY = Py * PBMap\TileSize - (Int(Py) * PBMap\TileSize)
    *Drawing\TargetLocation\Latitude = PBMap\TargetLocation\Latitude
    *Drawing\TargetLocation\Longitude = PBMap\TargetLocation\Longitude
    ;Main drawing stuff
    StartVectorDrawing(CanvasVectorOutput(PBMap\Gadget))
    DrawTiles(*Drawing)
    DrawTrack(*Drawing)
    DrawMarker(*Drawing)
    DrawPointer(*Drawing)
    ;- Display how many images in cache
    VectorFont(FontID(PBMap\Font), 30)
    VectorSourceColor(RGBA(0, 0, 0, 80))
    MovePathCursor(50,50)
    DrawVectorText(Str(MapSize(PBMap\MemCache\Images())))
    MovePathCursor(50,80)
    DrawVectorText(Str(ListSize(PBMap\TilesThreads())))
    StopVectorDrawing()    
  EndProcedure
  
  Procedure Refresh()
    Drawing()
  EndProcedure
  
  Procedure SetLocation(latitude.d, longitude.d, zoom = 15, Mode.i = #PB_Absolute)
    Select Mode
      Case #PB_Absolute
        PBMap\TargetLocation\Latitude = latitude
        PBMap\TargetLocation\Longitude = longitude
        PBMap\Zoom = zoom
      Case #PB_Relative
        PBMap\TargetLocation\Latitude  + latitude
        PBMap\TargetLocation\Longitude + longitude
        PBMap\Zoom + zoom
    EndSelect
    If PBMap\Zoom > PBMap\ZoomMax : PBMap\Zoom = PBMap\ZoomMax : EndIf
    If PBMap\Zoom < PBMap\ZoomMin : PBMap\Zoom = PBMap\ZoomMin : EndIf
    LatLon2XY(@PBMap\TargetLocation, @PBMap\Drawing)
    ;Convert X, Y in tile.decimal into real pixels
    PBMap\Position\x = PBMap\Drawing\Position\x * PBMap\TileSize
    PBMap\Position\y = PBMap\Drawing\Position\y * PBMap\TileSize 
    PBMap\Drawing\PassNb = 1
    Drawing()
    If PBMap\CallBackLocation > 0
      CallFunctionFast(PBMap\CallBackLocation, @PBMap\TargetLocation)
    EndIf 
  EndProcedure
  
  Procedure  ZoomToArea()
    ;Source => http://gis.stackexchange.com/questions/19632/how-to-calculate-the-optimal-zoom-level-to-display-two-or-more-points-on-a-map
    ;bounding box in long/lat coords (x=long, y=lat)
    Protected MinY.d,MaxY.d,MinX.d,MaxX.d
    ForEach PBMap\track()
      If ListIndex(PBMap\track())=0 Or PBMap\track()\Longitude<MinX
        MinX=PBMap\track()\Longitude
      EndIf
      If ListIndex(PBMap\track())=0 Or PBMap\track()\Longitude>MaxX
        MaxX=PBMap\track()\Longitude
      EndIf
      If ListIndex(PBMap\track())=0 Or PBMap\track()\Latitude<MinY
        MinY=PBMap\track()\Latitude
      EndIf
      If ListIndex(PBMap\track())=0 Or PBMap\track()\Latitude>MaxY
        MaxY=PBMap\track()\Latitude
      EndIf
    Next 
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
      SetLocation(lat,lon, Round(zoom,#PB_Round_Down))
    Else
      SetLocation(PBMap\TargetLocation\Latitude,PBMap\TargetLocation\Longitude, 15)
    EndIf
  EndProcedure
  
  Procedure SetZoom(Zoom.i, mode.i = #PB_Relative)
    Select mode
      Case #PB_Relative
        PBMap\Zoom = PBMap\Zoom + zoom
      Case #PB_Absolute
        PBMap\Zoom = zoom
    EndSelect
    If PBMap\Zoom > PBMap\ZoomMax : PBMap\Zoom = PBMap\ZoomMax : EndIf
    If PBMap\Zoom < PBMap\ZoomMin : PBMap\Zoom = PBMap\ZoomMin : EndIf
    LatLon2XY(@PBMap\TargetLocation, @PBMap\Drawing)
    ;Convert X, Y in tile.decimal into real pixels
    PBMap\Position\X = PBMap\Drawing\Position\x * PBMap\TileSize
    PBMap\Position\Y = PBMap\Drawing\Position\y * PBMap\TileSize 
    ;First drawing
    Drawing()
    If PBMap\CallBackLocation > 0
      CallFunctionFast(PBMap\CallBackLocation, @PBMap\TargetLocation)
    EndIf 
  EndProcedure
  
  Procedure SetCallBackLocation(CallBackLocation.i)
    PBMap\CallBackLocation = CallBackLocation
  EndProcedure
  
  Procedure SetCallBackMainPointer(CallBackMainPointer.i)
    PBMap\CallBackMainPointer = CallBackMainPointer
  EndProcedure
  
   ;Zoom on x, y position relative to the canvas gadget
  Procedure SetZoomOnPosition(x, y, zoom)
    Protected MouseX.d, MouseY.d
    Protected OldPx.d, OldPy.d, OldMx.d, OldMy.d
    ;Fast and dirty code
    OldPx = PBMap\Position\x : OldPy = PBMap\Position\y
    OldMx = OldPx + GadgetWidth(PBMap\Gadget) / 2 - x
    OldMy = OldPy + GadgetHeight(PBMap\Gadget) / 2 - y
    PBMap\Zoom = PBMap\Zoom + zoom
    If PBMap\Zoom > PBMap\ZoomMax : PBMap\Zoom = PBMap\ZoomMax : EndIf
    If PBMap\Zoom < PBMap\ZoomMin : PBMap\Zoom = PBMap\ZoomMin : EndIf
    ;Centered Zoom
    LatLon2XY(@PBMap\TargetLocation, @PBMap\Drawing)
    ;Convert X, Y in tile.decimal into real pixels
    PBMap\Position\x = PBMap\Drawing\Position\x * PBMap\TileSize
    PBMap\Position\y = PBMap\Drawing\Position\y * PBMap\TileSize
    MouseX = PBMap\Position\x + GadgetWidth(PBMap\Gadget) / 2 - x
    MouseY = PBMap\Position\y + GadgetHeight(PBMap\Gadget) / 2 - y               
    ;Cross-multiply to get the new center
    PBMap\Position\x = (OldPx * MouseX) / OldMx
    PBMap\Position\y = (OldPy * MouseY) / OldMy
    ;PBMap tile position in tile.decimal
    PBMap\Drawing\Position\x = PBMap\Position\x / PBMap\TileSize
    PBMap\Drawing\Position\y = PBMap\Position\y / PBMap\TileSize
    PBMap\Drawing\PassNb = 1
    XY2LatLon(@PBMap\Drawing, @PBMap\TargetLocation)
    ;Start drawing
    Drawing()
    ;If CallBackLocation send Location to function
    If PBMap\CallBackLocation > 0
      CallFunctionFast(PBMap\CallBackLocation, @PBMap\TargetLocation)
    EndIf      
  EndProcedure  
  
  Procedure.d GetLatitude()
    Protected Value.d
    Value = PBMap\TargetLocation\Latitude
    ProcedureReturn Value
  EndProcedure
  
  Procedure.d GetLongitude()
    Protected Value.d
    Value = PBMap\TargetLocation\Longitude
    ProcedureReturn Value 
  EndProcedure
  
  Procedure.i GetZoom()
    Protected Value.d
    Value = PBMap\Zoom
    ProcedureReturn Value
  EndProcedure
  
  Procedure Event(Event.l)
    Protected Gadget.i
    Protected MouseX.i, MouseY.i
    Protected Marker.Position
    Protected *Drawing.DrawingParameters
    If IsGadget(PBMap\Gadget) And GadgetType(PBMap\Gadget) = #PB_GadgetType_Canvas 
      Select Event
        Case #PB_Event_Gadget ;{
          Gadget = EventGadget()
          Select Gadget
            Case PBMap\Gadget
              Select EventType()    
                Case #PB_EventType_MouseWheel
                  If PBMap\Options\WheelMouseRelative
                    ;Relative zoom (centered on the mouse)
                    SetZoomOnPosition(GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseX), GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseY), GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_WheelDelta))
                  Else
                    ;Absolute zoom (centered on the center of the map)
                    SetZoom(GetGadgetAttribute(PBMap\Gadget,#PB_Canvas_WheelDelta), #PB_Relative)
                  EndIf 
                Case #PB_EventType_LeftButtonDown
                  ;Check if we select a marker
                  MouseX = PBMap\Position\x - GadgetWidth(PBMap\Gadget) / 2 + GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseX)
                  MouseY = PBMap\Position\y - GadgetHeight(PBMap\Gadget) / 2 + GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseY)
                  ForEach PBMap\Marker()                   
                    LatLon2XY(@PBMap\Marker()\Location, @Marker)                   
                    Marker\x * PBMap\TileSize
                    Marker\y * PBMap\TileSize 
                    If Distance(Marker\x, Marker\y, MouseX, MouseY) < 8
                      PBMap\EditMarkerIndex = ListIndex(PBMap\Marker())  
                      Break
                    EndIf
                  Next
                  ;Mem cursor Coord
                  PBMap\MoveStartingPoint\x = GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseX) 
                  PBMap\MoveStartingPoint\y = GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseY) 
                Case #PB_EventType_MouseMove
                  If PBMap\MoveStartingPoint\x <> - 1
                    MouseX = GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseX) - PBMap\MoveStartingPoint\x
                    MouseY = GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseY) - PBMap\MoveStartingPoint\y
                    PBMap\Moving = #True
                    ;Move marker
                    If PBMap\EditMarkerIndex > -1
                      SelectElement(PBMap\Marker(), PBMap\EditMarkerIndex)
                      LatLon2XY(@PBMap\Marker()\Location, @Marker)
                      Marker\x + MouseX / PBMap\TileSize
                      Marker\y + MouseY / PBMap\TileSize
                      XY2LatLon(@Marker, @PBMap\Marker()\Location)                      
                    Else
                      ;New move values
                      PBMap\Position\x - MouseX
                      PBMap\Position\y - MouseY
                      ;PBMap tile position in tile.decimal
                      PBMap\Drawing\Position\x = PBMap\Position\x / PBMap\TileSize
                      PBMap\Drawing\Position\y = PBMap\Position\y / PBMap\TileSize
                      PBMap\Drawing\PassNb = 1
                      XY2LatLon(@PBMap\Drawing, @PBMap\TargetLocation)
                      ;If CallBackLocation send Location to function
                      If PBMap\CallBackLocation > 0
                        CallFunctionFast(PBMap\CallBackLocation, @PBMap\TargetLocation)
                      EndIf 
                    EndIf
                    Drawing()  
                    PBMap\MoveStartingPoint\x = GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseX) 
                    PBMap\MoveStartingPoint\y = GetGadgetAttribute(PBMap\Gadget, #PB_Canvas_MouseY)
                  EndIf 
                Case #PB_EventType_LeftButtonUp
                  PBMap\Moving = #False
                  PBMap\MoveStartingPoint\x = - 1
                  If PBMap\EditMarkerIndex > -1
                    PBMap\EditMarkerIndex = -1
                  Else ;Move Map
                    PBMap\Drawing\Position\x = PBMap\Position\x / PBMap\TileSize
                    PBMap\Drawing\Position\y = PBMap\Position\y / PBMap\TileSize
                    MyDebug("PBMap\Drawing\Position\x " + Str(PBMap\Drawing\Position\x) + " ; PBMap\Drawing\Position\y " + Str(PBMap\Drawing\Position\y) )
                    XY2LatLon(@PBMap\Drawing, @PBMap\TargetLocation)
                    Drawing() 
                  EndIf
                Case #PB_MAP_REDRAW  
                 Drawing() 
              EndSelect
          EndSelect
      EndSelect
    Else
      MessageRequester("Module PBMap", "You must use PBMapGadget before", #PB_MessageRequester_Ok )
      End
    EndIf  
    
  EndProcedure
EndModule

;-Exemple
CompilerIf #PB_Compiler_IsMainFile 
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
    #String_0
    #String_1
    #Gdt_LoadGpx
    #Gdt_AddMarker
  EndEnumeration
  
  Structure Location
    Longitude.d
    Latitude.d
  EndStructure
  
  Procedure UpdateLocation(*Location.Location)
    SetGadgetText(#String_0, StrD(*Location\Latitude))
    SetGadgetText(#String_1, StrD(*Location\Longitude))
    ProcedureReturn 0
  EndProcedure
  
  Procedure MyPointer(x.i, y.i)
    Protected color.l
    color=RGBA(0, 255, 0, 255)
    VectorSourceColor(color)
    MovePathCursor(x, y)
    AddPathLine(-16,-32,#PB_Path_Relative)
    AddPathCircle(16,0,16,180,0,#PB_Path_Relative)
    AddPathLine(-16,32,#PB_Path_Relative)
    VectorSourceColor(color)
    FillPath(#PB_Path_Preserve):VectorSourceColor(RGBA(0, 0, 0, 255)):StrokePath(1)
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
    ResizeGadget(#Gdt_Up,   WindowWidth(#Window_0) - 120 ,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_Down, WindowWidth(#Window_0) - 120 ,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Text_2,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Button_4,WindowWidth(#Window_0)-150,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Button_5,WindowWidth(#Window_0)-100,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Text_3,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#String_0,WindowWidth(#Window_0)-100,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#String_1,WindowWidth(#Window_0)-100,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Text_4,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_AddMarker,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_LoadGpx,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    PBMap::Refresh()
  EndProcedure
  
  ;- MAIN TEST
  If OpenWindow(#Window_0, 260, 225, 700, 571, "PBMap",  #PB_Window_SystemMenu | #PB_Window_MinimizeGadget | #PB_Window_TitleBar | #PB_Window_ScreenCentered | #PB_Window_SizeGadget)
    
    LoadFont(0, "Arial", 12)
    LoadFont(1, "Arial", 12, #PB_Font_Bold)
        
    TextGadget(#Text_1, 530, 50, 60, 15, "Movements")
    ButtonGadget(#Gdt_Left,  550, 100, 30, 30, Chr($E7))  : SetGadgetFont(#Gdt_Left, FontID(0)) 
    ButtonGadget(#Gdt_Right, 610, 100, 30, 30, Chr($E8))  : SetGadgetFont(#Gdt_Right, FontID(0)) 
    ButtonGadget(#Gdt_Up,    580, 070, 30, 30, Chr($E9))  : SetGadgetFont(#Gdt_Up, FontID(0)) 
    ButtonGadget(#Gdt_Down,  580, 130, 30, 30, Chr($EA))  : SetGadgetFont(#Gdt_Down, FontID(0)) 
    TextGadget(#Text_2, 530, 160, 60, 15, "Zoom")
    ButtonGadget(#Button_4, 550, 180, 50, 30, " + ")      : SetGadgetFont(#Button_4, FontID(1)) 
    ButtonGadget(#Button_5, 600, 180, 50, 30, " - ")      : SetGadgetFont(#Button_5, FontID(1)) 
    TextGadget(#Text_3, 530, 230, 60, 15, "Latitude : ")
    StringGadget(#String_0, 600, 230, 90, 20, "")
    TextGadget(#Text_4, 530, 250, 60, 15, "Longitude : ")
    StringGadget(#String_1, 600, 250, 90, 20, "")
    ButtonGadget(#Gdt_AddMarker, 530, 280, 150, 30, "Add Marker")
    ButtonGadget(#Gdt_LoadGpx, 530, 310, 150, 30, "Load GPX")
    
    Define Event.i, Gadget.i, Quit.b = #False
    Define pfValue.d
    
    ;Our main gadget
    PBMap::InitPBMap(#Window_0)
    PBMap::MapGadget(#Map, 10, 10, 512, 512)
    PBMap::SetCallBackMainPointer(@MainPointer()) ;To change the Main Pointer
    PBMap::SetCallBackLocation(@UpdateLocation())
    PBMap::SetLocation(-36.8485,174.7633,10)
    ;PBMap::AddMarker(49.0446828398, 2.0349812508, -1, @MyPointer())
    
    Repeat
      Event = WaitWindowEvent()
      PBMap::Event(Event)
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
            Case #Button_4
              PBMap::SetZoom(1)
            Case #Button_5
              PBMap::SetZoom( - 1)
            Case #Gdt_LoadGpx
              PBMap::LoadGpxFile(OpenFileRequester("Choose a file to load", "", "*.gpx", 0))
              PBMap::ZoomToArea() ; <-To center the view, and zoom on the tracks
            Case #Gdt_AddMarker
              PBMap:: AddMarker(ValD(GetGadgetText(#String_0)), ValD(GetGadgetText(#String_1)), RGBA(Random(255), Random(255), Random(255),255))
          EndSelect
        Case #PB_Event_SizeWindow
          ResizeAll()
      EndSelect
    Until Quit = #True
    
    PBMap::Quit()
  EndIf
 
  CloseConsole()
  
CompilerEndIf

; IDE Options = PureBasic 5.42 LTS (Windows - x86)
; CursorPosition = 362
; FirstLine = 339
; Folding = ---------
; EnableUnicode
; EnableThread
; EnableXP
; DisableDebugger