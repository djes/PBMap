;************************************************************** 
; Program:           OSM (OpenStreetMap Module) 
; Author:            Thyphoon And Djes
; Date:              Mai 17, 2016
; License:           Free, unrestricted, credit appreciated 
;                    but not required.
; Note:              Please share improvement !
; Thanks:            Progi1984, 
;************************************************************** 

CompilerIf #PB_Compiler_Thread = #False
  MessageRequester("Warning !!","You must enable ThreadSafe support in compiler options",#PB_MessageRequester_Ok )
  End
CompilerEndIf 

EnableExplicit

InitNetwork()
UsePNGImageDecoder()
UsePNGImageEncoder()

DeclareModule OSM
  Declare InitOSM()
  Declare OSMGadget(Gadget.i, X.i, Y.i, Width.i, Height.i)
  Declare Event(Event.l)
  Declare SetLocation(latitude.d, longitude.d, zoom = 15)
  Declare DrawingThread(Null)
  Declare SetZoom(Zoom.i, mode.i = #PB_Relative)
  Declare LoadGpxFile(file.s);  
EndDeclareModule

Module OSM 
  
  EnableExplicit
  
  Structure Location
    Longitude.d
    Latitude.d
  EndStructure
  
  ;- Tile Structure
  Structure Tile
    x.d
    y.d
    OSMTileX.i
    OSMTileY.i
    OSMZoom.i
    nImage.i
    GetImageThread.i
  EndStructure
  
  Structure DrawingParameters
    x.d
    y.d
    OSMTileX.i
    OSMTileY.i
    OSMZoom.i
    DeltaX.i
    DeltaY.i
    PassNb.i
  EndStructure  
  
  Structure TileThread
    GetImageThread.i
    *Tile.Tile
  EndStructure
  
  Structure Pixel
    x.i
    y.i
  EndStructure
  
  Structure ImgMemCach
    nImage.i
    Zoom.i
    XTile.i
    YTile.i
    Usage.i
  EndStructure
  
  Structure TileMemCach
    List Image.ImgMemCach()
    Mutex.i
    Semaphore.i
  EndStructure
  
  ;-OSM Structure
  Structure OSM
    Gadget.i                                ; Canvas Gadget Id 
    
    TargetLocation.Location                 ; Latitude and Longitude from focus point
    *Drawing.DrawingParameters                         ; Focus Tile coord
    
    Position.Pixel                          ; Actual focus Point coords in pixels
    MoveStartingPoint.Pixel                       ; Start mouse position coords when dragging the map
    
    ServerURL.s                             ; Web URL ex: http://tile.openstreetmap.org/
    ZoomMin.i                               ; Min Zoom supported by server
    ZoomMax.i                               ; Max Zoom supported by server
    Zoom.i                                  ; Current zoom
    TileSize.i                              ; Tile size downloaded on the server ex : 256
    
    HDDCachePath.S                          ; Path where to load and save tiles downloaded from server
    MemCache.TileMemCach                    ; Image in memory cache
    List MapImageIndex.ImgMemCach()         ; Index from MemCache\Image() to construct map
    
    DrawingThreadMutex.i                    ;Only one main drawing thread
    EmergencyQuit.i
    Dirty.i                                 ;To signal that drawing need a refresh
    LoadingMutex.i
    DrawingMutex.i
    ;CurlMutex.i                             ;seems that I can't thread curl ! :(((((
    List TilesThreads.TileThread()
    
    MapImageMutex.i                         ; Mutex to lock
    
    List track.Location()                   ;to display a GPX track
    
  EndStructure
  
  Global OSM.OSM, Null.i
  
    ;- *** CURL specific ***
  
  Global *ReceiveHTTPToMemoryBuffer, ReceiveHTTPToMemoryBufferPtr.i, ReceivedData.s
  IncludeFile "libcurl.pbi" ; https://github.com/deseven/pbsamples/tree/master/crossplatform/libcurl
  
  ProcedureC ReceiveHTTPWriteToMemoryFunction(*ptr, Size.i, NMemB.i, *Stream)
    
    Protected SizeProper.i  = Size & 255
    Protected NMemBProper.i = NMemB
    
    If *ReceiveHTTPToMemoryBuffer = 0
      *ReceiveHTTPToMemoryBuffer = AllocateMemory(SizeProper * NMemBProper)
      If *ReceiveHTTPToMemoryBuffer = 0
        Debug "Problem allocating memory"
        End
      EndIf
    Else
      *ReceiveHTTPToMemoryBuffer = ReAllocateMemory(*ReceiveHTTPToMemoryBuffer, MemorySize(*ReceiveHTTPToMemoryBuffer) + SizeProper * NMemBProper)
      If *ReceiveHTTPToMemoryBuffer = 0
        Debug "Problem reallocating memory"
        End
      EndIf  
    EndIf
    
    CopyMemory(*ptr, *ReceiveHTTPToMemoryBuffer + ReceiveHTTPToMemoryBufferPtr, SizeProper * NMemBProper)
    ReceiveHTTPToMemoryBufferPtr + SizeProper * NMemBProper
    
    ProcedureReturn SizeProper * NMemBProper
    
  EndProcedure
  
  Procedure.i CurlReceiveHTTPToMemory(URL$, ProxyURL$="", ProxyPort$="", ProxyUser$="", ProxyPassword$="")
    
    Protected *Buffer, curl.i, Timeout.i, res.i
    
    ;Debug "ReceiveHTTPToMemory" + URL$ + ProxyURL$ + ProxyPort$ + ProxyUser$ + ProxyPassword$
    
    If Len(URL$)
      
      curl  = curl_easy_init()
      
      If curl
        
        Timeout = 3
        
        curl_easy_setopt(curl, #CURLOPT_URL, str2curl(URL$))
        curl_easy_setopt(curl, #CURLOPT_SSL_VERIFYPEER, 0)
        curl_easy_setopt(curl, #CURLOPT_SSL_VERIFYHOST, 0)
        curl_easy_setopt(curl, #CURLOPT_HEADER, 0)      
        curl_easy_setopt(curl, #CURLOPT_TIMEOUT, Timeout)
        
        If Len(ProxyURL$)
          ;curl_easy_setopt(curl, #CURLOPT_HTTPPROXYTUNNEL, #True)
          If Len(ProxyPort$)
            ProxyURL$ + ":" + ProxyPort$
          EndIf
          Debug ProxyURL$
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
            Debug "Problem allocating buffer"         
          EndIf        
          ;curl_easy_cleanup(curl) ;Was its original place but moved below as it seems more logical to me.
        Else
          Debug "CURL NOT OK"
        EndIf
        
        curl_easy_cleanup(curl)
        
      Else
        Debug "Can't Init CURL"
      EndIf
      
    EndIf
    
    Debug "Curl Buffer : " + Str(*Buffer)
    
    ProcedureReturn *Buffer
    
  EndProcedure
  ;- ***

  Procedure InitOSM()
    
    Protected Result.i
    
    OSM\HDDCachePath = GetTemporaryDirectory()
    OSM\ServerURL = "http://tile.openstreetmap.org/"
    OSM\ZoomMin = 0
    OSM\ZoomMax = 18
    OSM\MoveStartingPoint\x = - 1
    OSM\TileSize = 256
    OSM\MemCache\Mutex = CreateMutex()
    OSM\LoadingMutex = CreateMutex()
    OSM\DrawingMutex = CreateMutex()
    ;OSM\CurlMutex = CreateMutex()
    OSM\DrawingThreadMutex = CreateMutex()
    OSM\EmergencyQuit = #False
    OSM\Dirty = #False
    
    ;-*** PROXY
    
    Global Proxy = #True
    
;- => Use this to customise your preferences    
;     Result = CreatePreferences(GetHomeDirectory() + "OSM.prefs")
;     If Proxy
;       PreferenceGroup("PROXY")
;       WritePreferenceString("ProxyURL", "myproxy.fr")
;       WritePreferenceString("ProxyPort", "myproxyport")
;       WritePreferenceString("ProxyUser", "myproxyname")     
;     EndIf
;     If Result 
;       ClosePreferences()    
;     EndIf
    
    Result = OpenPreferences(GetHomeDirectory() + "OSM.prefs")
    If Proxy
      PreferenceGroup("PROXY")       
      Global ProxyURL$  = ReadPreferenceString("ProxyURL", "")  ;InputRequester("ProxyServer", "Do you use a Proxy Server? Then enter the full url:", "")
      Global ProxyPort$ = ReadPreferenceString("ProxyPort", "") ;InputRequester("ProxyPort"  , "Do you use a specific port? Then enter it", "")
      Global ProxyUser$ = ReadPreferenceString("ProxyUser", "") ;InputRequester("ProxyUser"  , "Do you use a user name? Then enter it", "")
      Global ProxyPassword$ = InputRequester("ProxyPass"  , "Do you use a password ? Then enter it", "")
    EndIf
    If Result
      ClosePreferences()
    EndIf
    
    curl_global_init(#CURL_GLOBAL_ALL);
    
  EndProcedure
  ;- **
  
  Procedure OSMGadget(Gadget.i, X.i, Y.i, Width.i, Height.i)
    If Gadget = #PB_Any
      OSM\Gadget = CanvasGadget(OSM\Gadget, X, Y, Width, Height)
    Else
      OSM\Gadget = Gadget
      CanvasGadget(OSM\Gadget, X, Y, Width, Height)
    EndIf 
  EndProcedure
  
  
  Procedure LatLon2XY(*Location.Location, *Tile.Tile)
    Protected n.d = Pow(2.0, OSM\Zoom)
    Protected LatRad.d = Radian(*Location\Latitude)
    *Tile\x = n * ( (*Location\Longitude + 180.0) / 360.0)
    *Tile\y = n * ( 1.0 - Log(Tan(LatRad) + 1.0/Cos(LatRad)) / #PI ) / 2.0
    Debug "Latitude : " + StrD(*Location\Latitude) + " ; Longitude : " + StrD(*Location\Longitude)
    Debug "Tile X : " + Str(*Tile\x) + " ; Tile Y : " + Str(*Tile\y)
  EndProcedure
  
  Procedure XY2LatLon(*Tile.Tile, *Location.Location)
    Protected n.d = Pow(2.0, OSM\Zoom)
    Protected LatitudeRad.d
    *Location\Longitude  = *Tile\x / n * 360.0 - 180.0
    LatitudeRad = ATan(SinH(#PI * (1.0 - 2.0 * *Tile\y / n)))
    *Location\Latitude = Degree(LatitudeRad)
  EndProcedure
  
  Procedure getPixelCoorfromLocation(*Location.Location, *Pixel.Pixel) ; TODO to Optimize 
    Protected mapWidth.l    = Pow(2,OSM\Zoom+8)
    Protected mapHeight.l   = Pow(2,OSM\Zoom+8)
    Protected x1.l,y1.l
    
    Protected deltaX = OSM\Position\x - Int(OSM\TargetTile\x) * OSM\TileSize  ;Get the position into the tile
    Protected deltaY = OSM\Position\y - Int(OSM\TargetTile\y) * OSM\TileSize
    
    ; get x value
    x1 = (*Location\Longitude+180)*(mapWidth/360)
    ; convert from degrees To radians
    Protected latRad.d = *Location\Latitude*#PI/180;
    
    Protected mercN.d = Log(Tan((#PI/4)+(latRad/2)));
    y1     = (mapHeight/2)-(mapWidth*mercN/(2*#PI)) ;
    
    Protected x2.l, y2.l
    ; get x value
    x2 = (OSM\TargetLocation\Longitude+180)*(mapWidth/360)
    ; convert from degrees To radians
    latRad = OSM\TargetLocation\Latitude*#PI/180;
                                                ; get y value
    mercN = Log(Tan((#PI/4)+(latRad/2)))        ;
    y2     = (mapHeight/2)-(mapWidth*mercN/(2*#PI));
    
    *Pixel\x=GadgetWidth(OSM\Gadget)/2  - (x2-x1) + deltaX
    *Pixel\y=GadgetHeight(OSM\Gadget)/2 - (y2-y1) + deltaY
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
      ClearList(OSM\track())
      For child = 1 To XMLChildCount(*MainNode)
        *child = ChildXMLNode(*MainNode, child)
        AddElement(OSM\track())
        If ExamineXMLAttributes(*child)
          While NextXMLAttribute(*child)
            Select XMLAttributeName(*child)
              Case "lat"
                OSM\track()\Latitude=ValD(XMLAttributeValue(*child))
              Case "lon"
                OSM\track()\Longitude=ValD(XMLAttributeValue(*child))
            EndSelect
          Wend
        EndIf
      Next 
    EndIf
  EndProcedure
  
  Procedure.i GetTileFromMem(Zoom.i, XTile.i, YTile.i)
    
    Protected nImage.i = -1
    
    Debug "Check if we have this image in memory"
    
    LockMutex(OSM\LoadingMutex)   
    LockMutex(OSM\MemCache\Mutex)    
    ForEach OSM\MemCache\Image()
      If Zoom = OSM\MemCache\Image()\Zoom And OSM\MemCache\Image()\xTile = XTile And OSM\MemCache\Image()\yTile = YTile
        nImage = OSM\MemCache\Image()\nImage
        Debug "Load from MEM Tile X : " + Str(XTile) + " ; Tile Y : " + Str(YTile) + " nImage:" + Str(nImage)
        Break;
             ;ElseIf Zoom<>OSM\MemCache\Image()\Zoom
             ;        DeleteElement(OSM\MemCache\Image())
      EndIf 
    Next 
    UnlockMutex(OSM\MemCache\Mutex)
    UnlockMutex(OSM\LoadingMutex)   
    
    ProcedureReturn nImage
    
  EndProcedure
  
  Procedure.i GetTileFromHDD(Zoom.i, XTile.i, YTile.i)
    
    Protected nImage.i
    Protected CacheFile.s = "OSM_" + Str(Zoom) + "_" + Str(XTile) + "_" + Str(YTile) + ".png"
    
    Debug "Check if we have this image on HDD"
    
    If FileSize(OSM\HDDCachePath + cacheFile) > 0
      nImage = LoadImage(#PB_Any, OSM\HDDCachePath + CacheFile)
      
      If IsImage(nImage)
        Debug "Load from HDD Tile " + CacheFile
        ProcedureReturn nImage
      EndIf 
      
    EndIf
    
    ProcedureReturn -1
    
  EndProcedure
  
  Procedure.i GetTileFromWeb(Zoom.i, XTile.i, YTile.i)
    
    Protected *Buffer
    Protected nImage.i = -1
    
    Protected TileURL.s = OSM\ServerURL + Str(Zoom) + "/" + Str(XTile) + "/" + Str(YTile) + ".png"
    ; Test if in cache else download it
    Protected CacheFile.s = "OSM_" + Str(Zoom) + "_" + Str(XTile) + "_" + Str(YTile) + ".png"
    
    Debug "Check if we have this image on Web"
    
    If Proxy
      ;LockMutex(OSM\CurlMutex)             ;Seems no more necessary
      *Buffer = CurlReceiveHTTPToMemory(TileURL, ProxyURL$, ProxyPort$, ProxyUser$, ProxyPassword$)
      ;UnlockMutex(OSM\CurlMutex)
    Else
      *Buffer = ReceiveHTTPMemory(TileURL)  ;TODO to thread by using #PB_HTTP_Asynchronous
    EndIf
    Debug "Image buffer " + Str(*Buffer)
    
    If *Buffer
      LockMutex(OSM\LoadingMutex)
      nImage = CatchImage(#PB_Any, *Buffer, MemorySize(*Buffer))
      UnlockMutex(OSM\LoadingMutex)
      
      If IsImage(nImage)
        Debug "Load from web " + TileURL + " as Tile nb " + nImage
        LockMutex(OSM\LoadingMutex)
        SaveImage(nImage, OSM\HDDCachePath + CacheFile, #PB_ImagePlugin_PNG)
        UnlockMutex(OSM\LoadingMutex)
        FreeMemory(*Buffer)
      Else
        Debug "Can't catch image " + TileURL
        nImage = -1
        ;ShowMemoryViewer(*Buffer, MemorySize(*Buffer))
      EndIf
    Else
      Debug "Problem loading from web " + TileURL  
    EndIf      
    
    ProcedureReturn nImage
    
  EndProcedure
  
  Procedure GetImageThread(*Tile.Tile)
    
    Protected *CacheImagePtr
    Protected nImage.i = -1
    
    LockMutex(OSM\LoadingMutex)
    
    If OSM\EmergencyQuit = 0
      LockMutex(OSM\MemCache\Mutex) 
      *CacheImagePtr = AddElement(OSM\MemCache\Image())
      Debug " CacheImagePtr : " + Str(*CacheImagePtr)
      OSM\MemCache\Image()\xTile = *Tile\OSMTileX
      OSM\MemCache\Image()\yTile = *Tile\OSMTileY
      OSM\MemCache\Image()\Zoom = *Tile\OSMZoom
      OSM\MemCache\Image()\nImage = -1  ;By now, this tile is in "loading" state, for thread synchro
      UnlockMutex(OSM\MemCache\Mutex)
      nImage = GetTileFromHDD(*Tile\OSMZoom, *Tile\OSMTileX, *Tile\OSMTileY)
      If nImage = -1 And OSM\EmergencyQuit = 0
        nImage = GetTileFromWeb(*Tile\OSMZoom, *Tile\OSMTileX, *Tile\OSMTileY)
      EndIf
      LockMutex(OSM\MemCache\Mutex)
      If nImage <> -1 And OSM\EmergencyQuit = 0
        Debug "Adding tile " + Str(nImage) + " to mem cache"
        ;AddTileToMemCache(Zoom, XTile, YTile, nImage)
        OSM\MemCache\Image()\nImage = nImage
        Debug "Image nb " + Str(nImage) + " successfully added to mem cache"   
      Else
        Debug "Error GetImageThread procedure, tile not loaded - Zoom:" + Str(*Tile\OSMZoom) + " X:" + Str(*Tile\OSMTileX) + " Y:" + Str(*Tile\OSMTileY)
        DeleteElement(OSM\MemCache\Image())
        nImage = -1
      EndIf
      UnlockMutex(OSM\MemCache\Mutex)
    EndIf
    *Tile\nImage = nImage
    UnlockMutex(OSM\LoadingMutex)
    
  EndProcedure
  
  Procedure DrawTile(*Tile.Tile)
    
    Protected x = *Tile\x - OSM\DeltaX
    Protected y = *Tile\y - OSM\DeltaY
    
    Debug "  Drawing tile nb " + " X : " + Str(x) + " Y : " + Str(y)
    
    LockMutex(OSM\DrawingMutex)
    If OSM\EmergencyQuit = 0 ;Quit before drawing
      StartDrawing(CanvasOutput(OSM\Gadget))  
      If IsImage(*Tile\nImage)          
        DrawImage(ImageID(*Tile\nImage), x, y)
        DrawText( x, y, Str(x) + ", " + Str(y))
      Else
        Debug "Image missing"
        OSM\Dirty = #True ;Signal that this image is missing so we should have to redraw
      EndIf
      StopDrawing()
    EndIf
    UnlockMutex(OSM\DrawingMutex)
    
  EndProcedure
  
  Procedure DrawTiles()
    
    Protected x.i, y.i
    
    Protected tx = Int(OSM\TargetTile\x)  ;Don't forget the Int() !
    Protected ty = Int(OSM\TargetTile\y)
    
    Protected CenterX = GadgetWidth(OSM\Gadget) / 2
    Protected CenterY = GadgetHeight(OSM\Gadget) / 2
    
    Protected nx = CenterX / OSM\TileSize ;How many tiles around the point
    Protected ny = CenterY / OSM\TileSize
    
    Debug "Drawing tiles"
    
    For y = - ny To ny
      For x = - nx To nx
        
        If OSM\EmergencyQuit
          Break 2
        EndIf
        
        Protected *NewTile.Tile = AllocateMemory(SizeOf(Tile))
        If *NewTile
          With *NewTile
            
            AddElement(OSM\TilesThreads())
            OSM\TilesThreads()\Tile = *NewTile
            \x = CenterX + x * OSM\TileSize
            \y = CenterY + y * OSM\TileSize
            \OSMTileX = tx + x
            \OSMTileY = ty + y
            \OSMZoom  = OSM\Zoom
            
            ;Check if the image exists, if not, load it in the background
            \nImage = GetTileFromMem(\OSMZoom, \OSMTileX, \OSMTileY)
            If \nImage = -1 
              \GetImageThread = CreateThread(@GetImageThread(), *NewTile)

              OSM\TilesThreads()\GetImageThread = \GetImageThread
            EndIf
            Debug " Creating get image thread nb " + Str(\GetImageThread)
            DrawTile(*NewTile)
            
          EndWith  
          
        Else
          Debug" Error, can't create a new tile."
          Break 2
        EndIf 
      Next
    Next
    
    ForEach OSM\TilesThreads()
      If IsThread(OSM\TilesThreads()\GetImageThread) = 0
        FreeMemory(OSM\TilesThreads()\Tile)
        DeleteElement(OSM\TilesThreads())
      EndIf         
    Next
    
  EndProcedure
  
  Procedure DrawTrack()
    
    Protected Pixel.Pixel
    Protected Location.Location
    Protected n.i = 0, x.i, y.i
    
    StartDrawing(CanvasOutput(OSM\Gadget))
    ForEach OSM\track()
      n=n+1
      If @OSM\TargetLocation\Latitude<>0 And  @OSM\TargetLocation\Longitude<>0
        getPixelCoorfromLocation(@OSM\track(),@Pixel)
        x=Pixel\x
        y=Pixel\y
        If x>0 And y>0 And x<GadgetWidth(OSM\Gadget) And y<GadgetHeight(OSM\Gadget)
          Circle(x,y,2,#Green)
        EndIf
      EndIf 
    Next
    StopDrawing()
    
  EndProcedure  
  
  Procedure DrawingThread(*Drawing.DrawingParameters)
    
    Debug "--------- Main drawing thread ------------"
    OSM\Dirty = #False
    
    LockMutex(OSM\DrawingThreadMutex) ; Only one main drawing thread at once
    
    Protected CenterX = GadgetWidth(OSM\Gadget) / 2
    Protected CenterY = GadgetHeight(OSM\Gadget) / 2
    
    DrawTiles()
    
    LockMutex(OSM\DrawingMutex)
    StartDrawing(CanvasOutput(OSM\Gadget))
    ;DrawTrack()
    Circle(CenterX, CenterY, 5, #Red)
    StopDrawing()
    UnlockMutex(OSM\DrawingMutex)
    
    UnlockMutex(OSM\DrawingThreadMutex)
    
    ;- Redraw
    ;If something was not correctly drawn, redraw after a while
    If OSM\Dirty
      Debug "Something was dirty ! We try again to redraw"
      ;Delay(250)
      
      *Drawing\PassNb + 1
      CreateThread(@DrawingThread(), *Drawing)
    EndIf
    
    *Drawing\PassNb - 1
    If *Drawing\PassNb = 0
      FreeMemory(*TargetTile)
    EndIf
    
  EndProcedure
  
  Procedure SetLocation(latitude.d, longitude.d, zoom = 15)
    
    If zoom > OSM\ZoomMax : zoom = OSM\ZoomMax : EndIf
    If zoom < OSM\ZoomMin : zoom = OSM\ZoomMin : EndIf
    OSM\Zoom = zoom
    OSM\TargetLocation\Latitude = latitude
    OSM\TargetLocation\Longitude = longitude
    LatLon2XY(@OSM\TargetLocation, @OSM\TargetTile)
    OSM\Position\x = OSM\TargetTile\x * OSM\TileSize ;Convert X, Y in tile.decimal into real pixels
    OSM\Position\y = OSM\TargetTile\y * OSM\TileSize
    OSM\DeltaX = OSM\Position\x - Int(OSM\Position\x / OSM\TileSize) * OSM\TileSize
    OSM\DeltaY = OSM\Position\y - Int(OSM\Position\y / OSM\TileSize) * OSM\TileSize
    CreateThread(@DrawingThread(), Null)
    
  EndProcedure
  
  Procedure SetZoom(Zoom.i, mode.i = #PB_Relative)
    
    Select mode
      Case #PB_Relative
        OSM\Zoom = OSM\Zoom + zoom
      Case #PB_Absolute
        OSM\Zoom = zoom
    EndSelect
    
    If OSM\Zoom > OSM\ZoomMax : OSM\Zoom = OSM\ZoomMax : EndIf
    If OSM\Zoom < OSM\ZoomMin : OSM\Zoom = OSM\ZoomMin : EndIf
    LatLon2XY(@OSM\TargetLocation, @OSM\TargetTile)
    OSM\Position\x = OSM\TargetTile\x * OSM\TileSize ;Convert X, Y in tile.decimal into real pixels
    OSM\Position\y = OSM\TargetTile\y * OSM\TileSize
    OSM\DeltaX = OSM\Position\x - Int(OSM\Position\x / OSM\TileSize) * OSM\TileSize
    OSM\DeltaY = OSM\Position\y - Int(OSM\Position\y / OSM\TileSize) * OSM\TileSize
    CreateThread(@DrawingThread(), Null)
    
  EndProcedure
  
  Procedure Event(Event.l)
    
    Protected Gadget.i
    Protected MouseX.i, MouseY.i
    Protected OldX.i, OldY.i
    Protected TileX.d, TileY.d
    Protected *Drawing.DrawingParameters
    
    If IsGadget(OSM\Gadget) And GadgetType(OSM\Gadget) = #PB_GadgetType_Canvas 
      Select Event
        Case #PB_Event_Gadget ;{
          Gadget = EventGadget()
          Select Gadget
            Case OSM\Gadget
              Select EventType()
                Case #PB_EventType_LeftButtonDown
                  ;Mem cursor Coord
                  OSM\MoveStartingPoint\x = GetGadgetAttribute(OSM\Gadget, #PB_Canvas_MouseX) 
                  OSM\MoveStartingPoint\y = GetGadgetAttribute(OSM\Gadget, #PB_Canvas_MouseY) 
                Case #PB_EventType_MouseMove
                  If OSM\MoveStartingPoint\x <> - 1
                    ;Need a refresh
                    ;OSM\EmergencyQuit = #True
                    MouseX = GetGadgetAttribute(OSM\Gadget, #PB_Canvas_MouseX) - OSM\MoveStartingPoint\x
                    MouseY = GetGadgetAttribute(OSM\Gadget, #PB_Canvas_MouseY) - OSM\MoveStartingPoint\y
                    ;Old move values 
                    OldX = OSM\Position\x 
                    OldY = OSM\Position\y
                    ;New move values
                    OSM\Position\x - MouseX
                    OSM\Position\y - MouseY
                    ;OSM tile position in tile.decimal
                    TileX = OSM\Position\x / OSM\TileSize
                    TileY = OSM\Position\y / OSM\TileSize
                    *Drawing = AllocateMemory(SizeOf(*DrawingParameters))
                    ;Pixel shift
                    *Drawing\DeltaX = OSM\Position\x - Int(TileX) * OSM\TileSize
                    *Drawing\DeltaY = OSM\Position\y - Int(TileY) * OSM\TileSize
                    ;Moved to a new tile ?
                    If (Int(OSM\Position\x / OSM\TileSize)) <> (Int(OldX / OSM\TileSize)) Or (Int(OSM\Position\y / OSM\TileSize)) <> (Int(OldY / OSM\TileSize)) 
                      Debug "--- New tile"
                      *TargetTile\x = TileX
                      *TargetTile\y = TileY
                      Debug "OSM\Position\x " + Str(OSM\Position\x) + " ; OSM\Position\y " + Str(OSM\Position\y) 
                      XY2LatLon(*Drawing, @OSM\TargetLocation)
                      Debug "OSM\TargetTile\x " + StrD(*Drawing\x) + " ; OSM\TargetTile\y "  + StrD(*Drawing\y) 
                    EndIf
                    OSM\EmergencyQuit = #False
                    *Drawing\PassNb = 1
                    CreateThread(@DrawingThread(), *Drawing)
                    OSM\MoveStartingPoint\x = GetGadgetAttribute(OSM\Gadget, #PB_Canvas_MouseX) 
                    OSM\MoveStartingPoint\y = GetGadgetAttribute(OSM\Gadget, #PB_Canvas_MouseY)
                  EndIf
                Case #PB_EventType_LeftButtonUp
                  OSM\MoveStartingPoint\x = - 1
                  OSM\TargetTile\x = OSM\Position\x / OSM\TileSize
                  OSM\TargetTile\y = OSM\Position\y / OSM\TileSize
                  Debug "OSM\Position\x " + Str(OSM\Position\x) + " ; OSM\Position\y " + Str(OSM\Position\y) 
                  XY2LatLon(@OSM\TargetTile, @OSM\TargetLocation)
                  ;Draw()
                  Debug "OSM\TargetTile\x " + StrD(OSM\TargetTile\x) + " ; OSM\TargetTile\y "  + StrD(OSM\TargetTile\y) 
                  ;SetGadgetText(#String_1, StrD(OSM\TargetLocation\Latitude))
                  ;SetGadgetText(#String_0, StrD(OSM\TargetLocation\Longitude))
              EndSelect
          EndSelect
      EndSelect
    Else
      MessageRequester("Module OSM", "You must use OSMGadget before", #PB_MessageRequester_Ok )
      End
    EndIf  
    
  EndProcedure
EndModule

Enumeration
  #Window_0
  #Map
  #Button_0
  #Button_1
  #Button_2
  #Button_3
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
EndEnumeration

;- Main
If OpenWindow(#Window_0, 260, 225, 700, 571, "OpenStreetMap",  #PB_Window_SystemMenu | #PB_Window_MinimizeGadget | #PB_Window_TitleBar | #PB_Window_ScreenCentered )
  
  OSM::InitOSM()
  LoadFont(0, "Wingdings", 12)
  LoadFont(1, "Arial", 12, #PB_Font_Bold)
  
  OSM::OSMGadget(#Map, 10, 10, 512, 512)
  
  TextGadget(#Text_1, 530, 50, 60, 15, "Movements : ")
  ButtonGadget(#Button_0, 550, 100, 30, 30, Chr($E7))  : SetGadgetFont(#Button_0, FontID(0)) 
  ButtonGadget(#Button_1, 610, 100, 30, 30, Chr($E8))  : SetGadgetFont(#Button_1, FontID(0)) 
  ButtonGadget(#Button_2, 580, 070, 30, 30, Chr($E9))  : SetGadgetFont(#Button_2, FontID(0)) 
  ButtonGadget(#Button_3, 580, 130, 30, 30, Chr($EA))  : SetGadgetFont(#Button_3, FontID(0)) 
  TextGadget(#Text_2, 530, 160, 60, 15, "Zoom : ")
  ButtonGadget(#Button_4, 550, 180, 50, 30, " + ")      : SetGadgetFont(#Button_4, FontID(1)) 
  ButtonGadget(#Button_5, 600, 180, 50, 30, " - ")      : SetGadgetFont(#Button_5, FontID(1)) 
  TextGadget(#Text_3, 530, 230, 60, 15, "Latitude : ")
  StringGadget(#String_0, 600, 230, 90, 20, "")
  TextGadget(#Text_4, 530, 250, 60, 15, "Longitude : ")
  StringGadget(#String_1, 600, 250, 90, 20, "")
  
  Define Event.i, Gadget.i, Quit.b = #False
  Define pfValue.d
  OSM::SetLocation(49.04599, 2.03347, 17)
  ;OSM::SetLocation(49.0361165, 2.0456982)
  
  Repeat
    Event = WaitWindowEvent()
    
    OSM::Event(Event)
    Select Event
      Case #PB_Event_CloseWindow : Quit = 1
      Case #PB_Event_Gadget ;{
        Gadget = EventGadget()
        Select Gadget
          Case #Button_4
            OSM::SetZoom(1)
          Case #Button_5
            OSM::SetZoom( - 1)
        EndSelect
    EndSelect
  Until Quit = #True
EndIf
