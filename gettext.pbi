Procedure.s gettext(String.s = "")
  Protected Language.s = "EN_en"
  
  Select Language
      
    Case "EN_en"
      ProcedureReturn String
      
    Case "FR_fr"
      
      Select String
          
        Case "Identifier"
          ProcedureReturn("Identificateur")
          
        Default
          ProcedureReturn String
          
      EndSelect  
      
    Default
      ProcedureReturn String

  EndSelect
EndProcedure
; IDE Options = PureBasic 5.50 (Windows - x64)
; CursorPosition = 21
; Folding = -
; EnableXP