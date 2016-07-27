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
  Declare MapGadget(Gadget.i, X.i, Y.i, Width.i, Height.i)
  Declare Event(Event.l)
  Declare SetLocation(latitude.d, longitude.d, zoom = 15)
  Declare DrawingThread(Null)
  Declare SetZoom(Zoom.i, mode.i = #PB_Relative)
  Declare ZoomToArea()
  Declare SetCallBackLocation(*CallBackLocation)
  Declare LoadGpxFile(file.s);  
  Declare AddMarker(Latitude.d,Longitude.d,color.l=-1)
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
    Semaphore.i
    Dirty.i
    PassNB.i
    End.i
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
  
  Structure Marker
    Location.Location
    color.l
  EndStructure
  ;-OSM Structure
  Structure OSM
    Gadget.i                                ; Canvas Gadget Id 
    
    TargetLocation.Location                 ; Latitude and Longitude from focus point
    Drawing.DrawingParameters               ; Drawing parameters based on focus point
    
    CallBackLocation.i                      ; @Procedure(latitude.d,lontitude.d)
    
    Position.Pixel                          ; Actual focus Point coords in pixels
    MoveStartingPoint.Pixel                 ; Start mouse position coords when dragging the map
    
    ServerURL.s                             ; Web URL ex: http://tile.openstreetmap.org/
    ZoomMin.i                               ; Min Zoom supported by server
    ZoomMax.i                               ; Max Zoom supported by server
    Zoom.i                                  ; Current zoom
    TileSize.i                              ; Tile size downloaded on the server ex : 256
    
    HDDCachePath.S                          ; Path where to load and save tiles downloaded from server
    MemCache.TileMemCach                    ; Image in memory cache
    List MapImageIndex.ImgMemCach()         ; Index from MemCache\Image() to construct map
    
    Moving.i
    Dirty.i                                 ;To signal that drawing need a refresh
    ;CurlMutex.i                            ;seems that I can't thread curl ! :(((((
    List TilesThreads.TileThread()
    
    MapImageMutex.i                         ; Mutex to lock
    
    List track.Location()                   ;to display a GPX track
    List Marker.Marker()                    ; To diplay marker
    EditMarkerIndex.l
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
    ;OSM\CurlMutex = CreateMutex()
    OSM\Dirty = #False
    OSM\Drawing\Semaphore = CreateSemaphore()
    
    ;-*** PROXY
    
    Global Proxy = #False
    
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
    CreateThread(@DrawingThread(), @OSM\Drawing)
    
  EndProcedure
  ;- ***
  
  Procedure MapGadget(Gadget.i, X.i, Y.i, Width.i, Height.i)
    If Gadget = #PB_Any
      OSM\Gadget = CanvasGadget(OSM\Gadget, X, Y, Width, Height)
    Else
      OSM\Gadget = Gadget
      CanvasGadget(OSM\Gadget, X, Y, Width, Height)
    EndIf 
  EndProcedure
  
  ;*** Converts coords to tile.decimal
  Procedure LatLon2XY(*Location.Location, *Tile.Tile)
    Protected n.d = Pow(2.0, OSM\Zoom)
    Protected LatRad.d = Radian(*Location\Latitude)
    *Tile\x = n * ( (*Location\Longitude + 180.0) / 360.0)
    *Tile\y = n * ( 1.0 - Log(Tan(LatRad) + 1.0/Cos(LatRad)) / #PI ) / 2.0
    Debug "Latitude : " + StrD(*Location\Latitude) + " ; Longitude : " + StrD(*Location\Longitude)
    Debug "Tile X : " + Str(*Tile\x) + " ; Tile Y : " + Str(*Tile\y)
  EndProcedure
  
  ;*** Converts tile.decimal to coords
  Procedure XY2LatLon(*Tile.Tile, *Location.Location)
    Protected n.d = Pow(2.0, OSM\Zoom)
    Protected LatitudeRad.d
    *Location\Longitude  = *Tile\x / n * 360.0 - 180.0
    LatitudeRad = ATan(SinH(#PI * (1.0 - 2.0 * *Tile\y / n)))
    *Location\Latitude = Degree(LatitudeRad)
  EndProcedure
  
  Procedure GetPixelCoordFromLocation(*Location.Location, *Pixel.Pixel) ; TODO to Optimize 
    Protected mapWidth.l    = Pow(2,OSM\Zoom+8)
    Protected mapHeight.l   = Pow(2,OSM\Zoom+8)
    Protected x1.l,y1.l
    
    Protected deltaX = OSM\Position\x - Int(OSM\Drawing\x) * OSM\TileSize  ;Get the position into the tile
    Protected deltaY = OSM\Position\y - Int(OSM\Drawing\y) * OSM\TileSize
    
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
    
    *Pixel\x=GadgetWidth(OSM\Gadget)/2  - (x2-x1) - deltaX
    *Pixel\y=GadgetHeight(OSM\Gadget)/2 - (y2-y1) - deltaY
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
      nImage = CatchImage(#PB_Any, *Buffer, MemorySize(*Buffer))
      If IsImage(nImage)
        Debug "Load from web " + TileURL + " as Tile nb " + nImage
        SaveImage(nImage, OSM\HDDCachePath + CacheFile, #PB_ImagePlugin_PNG)
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
    
    LockMutex(OSM\MemCache\Mutex)
    ;Push and pop as we are threaded
    PushListPosition(OSM\MemCache\Image())
    *CacheImagePtr = AddElement(OSM\MemCache\Image())
    Debug " CacheImagePtr : " + Str(*CacheImagePtr)
    OSM\MemCache\Image()\xTile = *Tile\OSMTileX
    OSM\MemCache\Image()\yTile = *Tile\OSMTileY
    OSM\MemCache\Image()\Zoom = *Tile\OSMZoom
    OSM\MemCache\Image()\nImage = -1  ;By now, this tile is in "loading" state, for thread synchro
    PopListPosition(OSM\MemCache\Image())
    UnlockMutex(OSM\MemCache\Mutex)
    nImage = GetTileFromHDD(*Tile\OSMZoom, *Tile\OSMTileX, *Tile\OSMTileY)
    If nImage = -1
      nImage = GetTileFromWeb(*Tile\OSMZoom, *Tile\OSMTileX, *Tile\OSMTileY)
    EndIf
    LockMutex(OSM\MemCache\Mutex)
    ChangeCurrentElement(OSM\MemCache\Image(), *CacheImagePtr)
    If nImage <> -1
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
    *Tile\nImage = nImage
    
  EndProcedure
  
  Procedure DrawTile(*Tile.Tile)
    
    Protected x = *Tile\x 
    Protected y = *Tile\y 
    
    Debug "  Drawing tile nb " + " X : " + Str(*Tile\OSMTileX) + " Y : " + Str(*Tile\OSMTileX)
    Debug "  at coords " + Str(x) + "," + Str(y)
    
    If IsImage(*Tile\nImage)    
      MovePathCursor(x, y)
      DrawVectorImage(ImageID(*Tile\nImage))
      MovePathCursor(x, y)
      DrawVectorText(Str(x) + ", " + Str(y))
    Else
      Debug "Image missing"
      OSM\Drawing\Dirty = #True ;Signal that this image is missing so we should have to redraw
    EndIf
    
  EndProcedure
  
  Procedure DrawTiles(*Drawing.DrawingParameters)
    
    Protected x.i, y.i
    
    Protected tx = Int(*Drawing\x)  ;Don't forget the Int() !
    Protected ty = Int(*Drawing\y)
    
    Protected CenterX = GadgetWidth(OSM\Gadget) / 2
    Protected CenterY = GadgetHeight(OSM\Gadget) / 2
    
    Protected nx = CenterX / OSM\TileSize ;How many tiles around the point
    Protected ny = CenterY / OSM\TileSize
    
    ;Pixel shift, aka position in the tile
    Protected DeltaX = *Drawing\x * OSM\TileSize - (tx * OSM\TileSize)
    Protected DeltaY = *Drawing\y * OSM\TileSize - (ty * OSM\TileSize)
    
    Debug "Drawing tiles"
    
    For y = - ny - 1 To ny + 1
      For x = - nx - 1 To nx + 1
        
        ;Was quiting the loop if a move occured, giving maybe smoother movement
        ;If OSM\Moving
        ;  Break 2
        ;EndIf
        
        Protected *NewTile.Tile = AllocateMemory(SizeOf(Tile))
        If *NewTile
          With *NewTile
            
            ;Keep a track of tiles (especially to free memory)
            AddElement(OSM\TilesThreads())
            OSM\TilesThreads()\Tile = *NewTile
            
            ;New tile parameters
            \x = CenterX + x * OSM\TileSize - DeltaX
            \y = CenterY + y * OSM\TileSize - DeltaY
            \OSMTileX = tx + x
            \OSMTileY = ty + y
            \OSMZoom  = OSM\Zoom
            
            ;Check if the image exists
            \nImage = GetTileFromMem(\OSMZoom, \OSMTileX, \OSMTileY)
            If \nImage = -1 
              ;If not, load it in the background
              \GetImageThread = CreateThread(@GetImageThread(), *NewTile)
              OSM\TilesThreads()\GetImageThread = \GetImageThread
              Debug " Creating get image thread nb " + Str(\GetImageThread)
            EndIf
            DrawTile(*NewTile)
            
          EndWith  
          
        Else
          Debug" Error, can't create a new tile."
          Break 2
        EndIf 
      Next
    Next
    
    ;Free tile memory when the loading thread has finished
    ;TODO : exit this proc from drawtiles in a special "free ressources" task
    ForEach OSM\TilesThreads()
      If IsThread(OSM\TilesThreads()\GetImageThread) = 0
        FreeMemory(OSM\TilesThreads()\Tile)
        DeleteElement(OSM\TilesThreads())
      EndIf         
    Next
    
  EndProcedure
  
    Procedure Pointer(x.i, y.i, color.l = #Red)
    
    color=RGBA(255, 0, 0, 255)
    VectorSourceColor(color)
    MovePathCursor(x, y)
    AddPathLine(-8,-16,#PB_Path_Relative)
    AddPathCircle(8,0,8,180,0,#PB_Path_Relative)
    AddPathLine(-8,16,#PB_Path_Relative)
    ;FillPath(#PB_Path_Preserve) 
    ;ClipPath(#PB_Path_Preserve)
    AddPathCircle(0,-16,5,0,360,#PB_Path_Relative)
    VectorSourceColor(color)
    FillPath(#PB_Path_Preserve):VectorSourceColor(RGBA(0, 0, 0, 255)):StrokePath(1)
    
  EndProcedure
  
  Procedure  DrawTrack(*Drawing.DrawingParameters)
    
    Protected Pixel.Pixel
    Protected Location.Location
    Protected DeltaX = *Drawing\x * OSM\TileSize - (Int(*Drawing\x) * OSM\TileSize)
    Protected DeltaY = *Drawing\y * OSM\TileSize - (Int(*Drawing\y) * OSM\TileSize)

    If ListSize(OSM\track())>0
      
      ForEach OSM\track()
        If @OSM\TargetLocation\Latitude<>0 And  @OSM\TargetLocation\Longitude<>0
          GetPixelCoordFromLocation(@OSM\track(), @Pixel)
          If ListIndex(OSM\track())=0
            MovePathCursor(Pixel\X + DeltaX, Pixel\Y + DeltaY)
          Else
            AddPathLine(Pixel\X + DeltaX, Pixel\Y + DeltaY)
          EndIf 
          
        EndIf 
        
      Next
      VectorSourceColor(RGBA(0, 255, 0, 150))
      StrokePath(10, #PB_Path_RoundEnd|#PB_Path_RoundCorner)
      
    EndIf
    
  EndProcedure
  
  
  ; Add a Marker To the Map
  Procedure AddMarker(Latitude.d,Longitude.d,color.l=-1)
    AddElement(OSM\Marker())
    OSM\Marker()\Location\Latitude=Latitude
    OSM\Marker()\Location\Longitude=Longitude
    OSM\Marker()\color=color
  EndProcedure
  
  ; Draw all markers on the screen !
  Procedure  DrawMarker(*Drawing.DrawingParameters)
    Protected Pixel.Pixel
    
    Protected DeltaX = *Drawing\x * OSM\TileSize - (Int(*Drawing\x) * OSM\TileSize)
    Protected DeltaY = *Drawing\y * OSM\TileSize - (Int(*Drawing\y) * OSM\TileSize)

    ForEach OSM\Marker()
      If OSM\Marker()\Location\Latitude<>0 And  OSM\Marker()\Location\Longitude<>0
        GetPixelCoordFromLocation(OSM\Marker()\Location,@Pixel)
        If Pixel\X+ DeltaX>0 And Pixel\Y+ DeltaY>0 And Pixel\X+ DeltaX<GadgetWidth(OSM\Gadget) And Pixel\Y<GadgetHeight(OSM\Gadget) ; Only if visible ^_^
          Pointer(Pixel\X+ DeltaX,Pixel\Y+ DeltaY,OSM\Marker()\color)
        EndIf 
      EndIf 
    Next
  EndProcedure
  
  Procedure DrawingThread(*Drawing.DrawingParameters)
    
    Repeat
      
      WaitSemaphore(*Drawing\Semaphore)
      
      Debug "--------- Main drawing thread ------------"
           
      *Drawing\Dirty = #False
      Protected CenterX = GadgetWidth(OSM\Gadget) / 2
      Protected CenterY = GadgetHeight(OSM\Gadget) / 2
      
      StartVectorDrawing(CanvasVectorOutput(OSM\Gadget))
      DrawTiles(*Drawing)
      DrawTrack(*Drawing)
      DrawMarker(*Drawing)
      Pointer(CenterX, CenterY, #Red)
      StopVectorDrawing()
      
      ;- Redraw
      ;If something was not correctly drawn, redraw after a while
      If *Drawing\Dirty
        Debug "Something was dirty ! We try again to redraw"
        ;Delay(250)
        *Drawing\PassNb + 1
        SignalSemaphore(*Drawing\Semaphore)
        ;TODO : Could be nice to avoid multiple redraws when not moving anymore
        ;        Else
;          ;Clean the semaphore
;          Repeat
;          Until TrySemaphore(*Drawing\Semaphore) = 0
      EndIf
           
    Until *Drawing\End
    
  EndProcedure
  
  Procedure SetLocation(latitude.d, longitude.d, zoom = 15)
    
    OSM\TargetLocation\Latitude = latitude
    OSM\TargetLocation\Longitude = longitude
    
    OSM\Zoom = zoom
    
    If OSM\Zoom > OSM\ZoomMax : OSM\Zoom = OSM\ZoomMax : EndIf
    If OSM\Zoom < OSM\ZoomMin : OSM\Zoom = OSM\ZoomMin : EndIf
    
    LatLon2XY(@OSM\TargetLocation, @OSM\Drawing)
    ;Convert X, Y in tile.decimal into real pixels
    OSM\Position\X = OSM\Drawing\x * OSM\TileSize
    OSM\Position\Y = OSM\Drawing\y * OSM\TileSize 
    OSM\Drawing\PassNb = 1
    ;Start drawing
    SignalSemaphore(OSM\Drawing\Semaphore)
    ;***
    
  EndProcedure
  
   Macro Min(a,b)
    (Bool((a) <= (b)) * (a) + Bool((b) < (a)) * (b))
  EndMacro
  
  Macro Max(a,b)
    (Bool((a) >= (b)) * (a) + Bool((b) > (a)) * (b))
  EndMacro
  
  
    Procedure  ZoomToArea()
    ;Source => http://gis.stackexchange.com/questions/19632/how-to-calculate-the-optimal-zoom-level-to-display-two-or-more-points-on-a-map
    ;bounding box in long/lat coords (x=long, y=lat)
    Protected MinY.d,MaxY.d,MinX.d,MaxX.d
    ForEach OSM\track()
      If ListIndex(OSM\track())=0 Or OSM\track()\Longitude<MinX
        MinX=OSM\track()\Longitude
      EndIf
      If ListIndex(OSM\track())=0 Or OSM\track()\Longitude>MaxX
        MaxX=OSM\track()\Longitude
      EndIf
      If ListIndex(OSM\track())=0 Or OSM\track()\Latitude<MinY
        MinY=OSM\track()\Latitude
      EndIf
      If ListIndex(OSM\track())=0 Or OSM\track()\Latitude>MaxY
        MaxY=OSM\track()\Latitude
      EndIf
    Next 
    Protected DeltaX.d=MaxX-MinX                            ;assumption ! In original code DeltaX have no source
    Protected centerX.d=MinX+DeltaX/2                       ; assumption ! In original code CenterX have no source
    Protected paddingFactor.f= 1.2                          ;paddingFactor: this can be used to get the "120%" effect ThomM refers to. Value of 1.2 would get you the 120%.
    
    Protected ry1.d = Log((Sin(Radian(MinY)) + 1) / Cos(Radian(MinY)))
    Protected ry2.d = Log((Sin(Radian(MaxY)) + 1) / Cos(Radian(MaxY)))
    Protected ryc.d = (ry1 + ry2) / 2                                 
    Protected centerY.d = Degree(ATan(SinH(ryc)))                     
    
    Protected resolutionHorizontal.d = DeltaX / GadgetWidth(OSM\Gadget)
    
    Protected vy0.d = Log(Tan(#PI*(0.25 + centerY/360)));
    Protected vy1.d = Log(Tan(#PI*(0.25 + MaxY/360)))   ;
    Protected viewHeightHalf.d = GadgetHeight(OSM\Gadget)/2;
    Protected zoomFactorPowered.d = viewHeightHalf / (40.7436654315252*(vy1 - vy0))
    Protected resolutionVertical.d = 360.0 / (zoomFactorPowered * OSM\TileSize)    
    If resolutionHorizontal<>0 And resolutionVertical<>0
      Protected resolution.d = Max(resolutionHorizontal, resolutionVertical)* paddingFactor
      Protected zoom.d = Log(360 / (resolution * OSM\TileSize))/Log(2)
      
      Protected lon.d = centerX;
      Protected lat.d = centerY;
      
      SetLocation(lat,lon, Round(zoom,#PB_Round_Down))
    Else
      SetLocation(OSM\TargetLocation\Latitude,OSM\TargetLocation\Longitude, 15)
    EndIf
    
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
    
    LatLon2XY(@OSM\TargetLocation, @OSM\Drawing)
    ;Convert X, Y in tile.decimal into real pixels
    OSM\Position\X = OSM\Drawing\x * OSM\TileSize
    OSM\Position\Y = OSM\Drawing\y * OSM\TileSize 
    ;*** Creates a drawing thread and fill parameters
    OSM\Drawing\PassNb = 1
    ;Start drawing
    SignalSemaphore(OSM\Drawing\Semaphore)
    ;***
    
  EndProcedure
  
  
  Procedure SetCallBackLocation(CallBackLocation.i)
    OSM\CallBackLocation=CallBackLocation
  EndProcedure
  Procedure Event(Event.l)
    
    Protected Gadget.i
    Protected MouseX.i, MouseY.i
    Protected OldX.i, OldY.i
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
                    MouseX = GetGadgetAttribute(OSM\Gadget, #PB_Canvas_MouseX) - OSM\MoveStartingPoint\x
                    MouseY = GetGadgetAttribute(OSM\Gadget, #PB_Canvas_MouseY) - OSM\MoveStartingPoint\y
                    OSM\Moving = #True
                    ;Old move values 
                    OldX = OSM\Position\x 
                    OldY = OSM\Position\y
                    ;New move values
                    OSM\Position\x - MouseX
                    OSM\Position\y - MouseY
                    ;-*** Fill parameters and signal the drawing thread
                    ;OSM tile position in tile.decimal
                    OSM\Drawing\x = OSM\Position\x / OSM\TileSize
                    OSM\Drawing\y = OSM\Position\y / OSM\TileSize
                    OSM\Drawing\PassNb = 1
                    ;Moved to a new tile ?
                    ;If (Int(OSM\Position\x / OSM\TileSize)) <> (Int(OldX / OSM\TileSize)) Or (Int(OSM\Position\y / OSM\TileSize)) <> (Int(OldY / OSM\TileSize)) 
                    XY2LatLon(@OSM\Drawing, @OSM\TargetLocation)
                    ;EndIf
                    ;Start drawing
                    SignalSemaphore(OSM\Drawing\Semaphore)
                    ;- ***                   
                    OSM\MoveStartingPoint\x = GetGadgetAttribute(OSM\Gadget, #PB_Canvas_MouseX) 
                    OSM\MoveStartingPoint\y = GetGadgetAttribute(OSM\Gadget, #PB_Canvas_MouseY)
                    ;If CallBackLocation send Location to function
                    If OSM\CallBackLocation>0
                      CallFunctionFast(OSM\CallBackLocation, @OSM\TargetLocation)
                    EndIf 
                  EndIf
                Case #PB_EventType_LeftButtonUp
                  OSM\Moving = #False
                  OSM\MoveStartingPoint\x = - 1
                  OSM\Drawing\x = OSM\Position\x / OSM\TileSize
                  OSM\Drawing\y = OSM\Position\y / OSM\TileSize
                  Debug "OSM\Position\x " + Str(OSM\Position\x) + " ; OSM\Position\y " + Str(OSM\Position\y) 
                  XY2LatLon(@OSM\Drawing, @OSM\TargetLocation)
                  ;Draw()
                  Debug "OSM\Drawing\x " + StrD(OSM\Drawing\x) + " ; OSM\Drawing\y "  + StrD(OSM\Drawing\y) 
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
  
  Procedure ResizeAll()
    ResizeGadget(#Map,10,10,WindowWidth(#Window_0)-198,WindowHeight(#Window_0)-59)
    ResizeGadget(#Text_1,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_Left,WindowWidth(#Window_0)-150,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_Right,WindowWidth(#Window_0)-90,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_Up,WindowWidth(#Window_0)-110,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_Down,WindowWidth(#Window_0)-110,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Text_2,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Button_4,WindowWidth(#Window_0)-150,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Button_5,WindowWidth(#Window_0)-100,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Text_3,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#String_0,WindowWidth(#Window_0)-100,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#String_1,WindowWidth(#Window_0)-100,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Text_4,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_AddMarker,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
    ResizeGadget(#Gdt_LoadGpx,WindowWidth(#Window_0)-170,#PB_Ignore,#PB_Ignore,#PB_Ignore)
  EndProcedure
  
  If OpenWindow(#Window_0, 260, 225, 700, 571, "OpenStreetMap",  #PB_Window_SystemMenu | #PB_Window_MinimizeGadget | #PB_Window_TitleBar | #PB_Window_ScreenCentered | #PB_Window_SizeGadget)
    OSM::InitOSM()
    LoadFont(0, "Wingdings", 12)
    LoadFont(1, "Arial", 12, #PB_Font_Bold)
    
    OSM::MapGadget(#Map, 10, 10, 512, 512)
    
    TextGadget(#Text_1, 530, 50, 60, 15, "Movements : ")
    ButtonGadget(#Gdt_Left, 550, 100, 30, 30, Chr($E7))  : SetGadgetFont(#Gdt_Left, FontID(0)) 
    ButtonGadget(#Gdt_Right, 610, 100, 30, 30, Chr($E8))  : SetGadgetFont(#Gdt_Right, FontID(0)) 
    ButtonGadget(#Gdt_Up, 580, 070, 30, 30, Chr($E9))  : SetGadgetFont(#Gdt_Up, FontID(0)) 
    ButtonGadget(#Gdt_Down, 580, 130, 30, 30, Chr($EA))  : SetGadgetFont(#Gdt_Down, FontID(0)) 
    TextGadget(#Text_2, 530, 160, 60, 15, "Zoom : ")
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
    OSM::SetLocation(49.04599, 2.03347, 17)
    OSM::SetCallBackLocation(@UpdateLocation())
    
    Repeat
      Event = WaitWindowEvent()
      
      OSM::Event(Event)
      Select Event
        Case #PB_Event_CloseWindow : Quit = 1
        Case #PB_Event_Gadget ;{
          Gadget = EventGadget()
          Select Gadget
            Case #Gdt_Up
              ;OSM::Move(0,-0.5)
            Case #Gdt_Down
              ;OSM::Move(0,0.5)
            Case #Gdt_Left
              ;OSM::Move(-0.5,0)
            Case #Gdt_Right
              ;OSM::Move(0.5,0)
            Case #Button_4
              OSM::SetZoom(1)
            Case #Button_5
              OSM::SetZoom( - 1)
            Case #Gdt_LoadGpx
              OSM::LoadGpxFile(OpenFileRequester("Choisissez un fichier à charger", "", "*.gpx", 0))
              OSM::ZoomToArea() ; <-To center the view, and to viex all the track
            Case #Gdt_AddMarker
              OSM:: AddMarker(ValD(GetGadgetText(#String_0)),ValD(GetGadgetText(#String_1)),RGBA(Random(255),Random(255),Random(255),255))
          EndSelect
        Case #PB_Event_SizeWindow
          ResizeAll()
      EndSelect
    Until Quit = #True
  EndIf
CompilerEndIf

; IDE Options = PureBasic 5.42 LTS (Windows - x64)
; CursorPosition = 672
; FirstLine = 646
; Folding = ------
; EnableUnicode
; EnableThread
; EnableXP