CREATE OR REPLACE PACKAGE BODY Pkg_Lms_Bulk_Operation AS

  FUNCTION In_List(p_String IN VARCHAR2) RETURN Fixedvaluelist AS
    l_String LONG DEFAULT p_String || ',';
    l_Data   Fixedvaluelist := Fixedvaluelist();
    n        NUMBER;
  BEGIN
    LOOP
      EXIT WHEN l_String IS NULL;
      n := Instr(l_String, ',');
      l_Data.Extend;
      l_Data(l_Data.Count) := Ltrim(Rtrim(Substr(l_String, 1, n - 1)));
      l_String := Substr(l_String, n + 1);
    END LOOP;
  
    RETURN l_Data;
  END In_List;

  PROCEDURE Prc_Lms_Bulk_Download_Template(p_Org_Code  IN VARCHAR2,
                                           p_Tran_Type IN VARCHAR2,
                                           p_Retstr    OUT VARCHAR2,
                                           p_Retpara   OUT VARCHAR2) IS
    m_Retstr  VARCHAR2(4000);
    m_Err_Msg VARCHAR2(4000);
    m_Retpara VARCHAR2(4000);
    Err_Str_Null EXCEPTION;
  BEGIN
    SELECT Listagg(a.Sz_Fieldname, ',') Within GROUP(ORDER BY a.i_Parameter_Seq) Sz_Fieldname,
           Listagg(a.Sz_Tran_Api_Parameter, ',') Within GROUP(ORDER BY a.i_Parameter_Seq) Sz_Fields
      INTO m_Retstr, m_Retpara
      FROM (SELECT d.Sz_Parameter_Desc || ' (' ||
                   Decode(d.c_Mandatory_Yn, 'Y', 'M', 'N') || ')' Sz_Fieldname,
                   d.Sz_Tran_Api_Parameter,
                   d.i_Parameter_Seq
              FROM m_Lms_Bulk_Header h, m_Lms_Bulk_Details d
             WHERE h.Sz_Org_Code = d.Sz_Org_Code
               AND h.i_Tran_Srno = d.i_Tran_Srno
               AND h.Sz_Transaction_Type = d.Sz_Transaction_Type
               AND d.Sz_Org_Code = p_Org_Code
               AND d.Sz_Transaction_Type = p_Tran_Type) a;
    IF m_Retstr IS NULL THEN
      RAISE Err_Str_Null;
    END IF;
    p_Retstr  := m_Retstr;
    p_Retpara := m_Retpara;
  EXCEPTION
    WHEN Err_Str_Null THEN
      p_Retstr  := NULL;
      m_Err_Msg := 'Master configuration not found for Transaction Type::' ||
                   p_Tran_Type;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Download_Template',
                                                    p_Errmsg   => m_Err_Msg);
    
    WHEN OTHERS THEN
      p_Retstr  := NULL;
      m_Err_Msg := Substr(SQLERRM, 1, 2000) || '::' || p_Tran_Type;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Download_Template',
                                                    p_Errmsg   => m_Err_Msg);
  END Prc_Lms_Bulk_Download_Template;

  PROCEDURE Prc_Lms_Bulk_Level1_Validation(p_Org_Code  IN VARCHAR2,
                                           p_Tran_Type IN VARCHAR2,
                                           p_File_Name IN VARCHAR2 ---PIPE SEPERATED
                                           ) IS
    m_Tran_Table m_Lms_Bulk_Header.Sz_Tran_Table%TYPE;
    TYPE Type_Col IS TABLE OF VARCHAR2(4000);
    m_Rec_Columns    Type_Col;
    m_Datatype       VARCHAR2(2000);
    m_Size           NUMBER;
    m_Precision      NUMBER;
    m_Count          NUMBER := 0;
    m_Mandatory_Flag m_Lms_Bulk_Details.c_Mandatory_Yn%TYPE;
    m_Str            VARCHAR2(4000);
    m_Rowcount       NUMBER := 0;
    m_Err_Msg        VARCHAR2(4000);
    m_Colname        VARCHAR2(4000);
    m_Colname1       VARCHAR2(4000);
    m_Retmsg         VARCHAR2(4000);
    Err_Level1_Insert EXCEPTION;
    m_File_Name   VARCHAR2(4000);
    m_Filecnt     NUMBER := 0;
    m_Cnt         NUMBER := 0;
    m_Err_Cnt     NUMBER := 0;
    m_Tot_Cnt     NUMBER := 0;
    m_Err_Rec_Cnt NUMBER := 0;
    m_Outstr      VARCHAR2(100);
  BEGIN
    SELECT m.Sz_Tran_Table
      INTO m_Tran_Table
      FROM m_Lms_Bulk_Header m
     WHERE m.Sz_Org_Code = p_Org_Code
       AND m.Sz_Transaction_Type = p_Tran_Type;
  
    SELECT TRIM(Ut.Column_Name) Column_Name BULK COLLECT
      INTO m_Rec_Columns
      FROM User_Tab_Columns Ut
     WHERE Ut.Table_Name = m_Tran_Table
       AND Ut.Column_Name NOT IN ('SZ_STAGE2_ERR',
                                  'SZ_ERRMSG',
                                  'SZ_FILENAME',
                                  'DT_LASTUPDATED',
                                  'SZ_USERID',
                                  'ROW_SRNO',
                                  'C_VDT_FLAG',
                                  'SZ_ORG_CODE')
     ORDER BY Ut.Column_Id;
  
    m_Filecnt := Regexp_Count(p_File_Name, '[|]');
    IF m_Filecnt > 0 THEN
      FOR k IN 1 .. m_Filecnt LOOP
        m_File_Name := Regexp_Substr(p_File_Name, '[^|]+', 1, k);
        EXECUTE IMMEDIATE 'UPDATE ' || m_Tran_Table ||
                          ' SET SZ_ERRMSG=NULL WHERE SZ_FILENAME=''' ||
                          m_File_Name || '''';
      
        --getting count for perticular transaction table
        m_Str := 'select count(1) from ' || m_Tran_Table ||
                 ' where Sz_Org_Code=''' || p_Org_Code ||
                 ''' and Sz_Filename=''' || m_File_Name || '''';
        EXECUTE IMMEDIATE m_Str
          INTO m_Cnt;
        --end
      
        Prc_Lms_Bulk_Duplicate(p_Org_Code  => p_Org_Code,
                               p_Tran_Type => p_Tran_Type,
                               p_File_Name => m_File_Name,
                               p_Outstr    => m_Outstr);
        IF m_Outstr = '11' THEN
          UPDATE t_Lms_Bulk_Tran_Details a
             SET a.c_Maker_Status = 'R'
           WHERE a.Sz_Org_Code = p_Org_Code
             AND a.Sz_Transaction_Type = p_Tran_Type
             AND a.Sz_File_Name = m_File_Name
             AND a.c_Maker_Status = 'O';
          RETURN;
        END IF;
        FOR i IN m_Rec_Columns.First .. m_Rec_Columns.Last LOOP
          m_Colname  := m_Rec_Columns(i);
          m_Colname1 := m_Colname1 || '$' || m_Colname;
          m_Colname1 := TRIM(Leading '$' FROM m_Colname1);
          m_Colname1 := REPLACE(m_Colname1, '$', '||'',''||');
        
          SELECT COUNT(1)
            INTO m_Count
            FROM m_Lms_Bulk_Details d
           WHERE d.Sz_Org_Code = p_Org_Code
             AND d.Sz_Transaction_Type = p_Tran_Type
             AND d.Sz_Tran_Api_Parameter = m_Colname;
        
          IF m_Count > 0 THEN
            SELECT Upper(d.Sz_Parameter_Datatype) c_Fielddatatype,
                   Nvl(d.i_Parameter_Size, 20),
                   Nvl(d.Sz_Precision, 0),
                   TRIM(d.c_Mandatory_Yn) c_Mandatory_Yn
              INTO m_Datatype, m_Size, m_Precision, m_Mandatory_Flag
              FROM m_Lms_Bulk_Details d
             WHERE d.Sz_Org_Code = p_Org_Code
               AND d.Sz_Transaction_Type = p_Tran_Type
               AND d.Sz_Tran_Api_Parameter = m_Colname;
          END IF;
          /*Check mandatory validations*/
          IF (m_Mandatory_Flag = 'Y') THEN
            m_Err_Msg := '''###ERROR:' || m_Rec_Columns(i) || ' FOR ' ||
                         p_Tran_Type ||
                         ' TRANSACTION IS MANDATORY FIELD, SO IT CANNOT BE NULL OR BLANK. ''';
          
            m_Str := 'UPDATE ' || m_Tran_Table ||
                     ' SET SZ_ERRMSG = SZ_ERRMSG||' || m_Err_Msg ||
                     ' WHERE ' || m_Rec_Columns(i) ||
                     ' IS NULL and SZ_FILENAME=''' || m_File_Name || '''';
          
            EXECUTE IMMEDIATE m_Str;
            m_Rowcount    := SQL%ROWCOUNT;
            m_Err_Rec_Cnt := m_Err_Rec_Cnt + m_Rowcount;
          END IF;
          /*datatype validations*/
          IF m_Rowcount = 0 THEN
            IF m_Datatype = 'NUMBER' THEN
              m_Err_Msg := '''###ERROR:INVALID DATA TYPE FOR FIELD:' ||
                           m_Rec_Columns(i) || ' FOR ' || p_Tran_Type ||
                           ' TRANSACTION. DESIRED DATA TYPE SHOULD BE:' ||
                           m_Datatype || '''';
            
              m_Str := 'UPDATE ' || m_Tran_Table ||
                       ' SET SZ_ERRMSG = SZ_ERRMSG||' || m_Err_Msg ||
                       ' WHERE Is_Number(' || m_Rec_Columns(i) ||
                       ')=0 and SZ_FILENAME=''' || m_File_Name || '''';
            
              EXECUTE IMMEDIATE m_Str;
              m_Err_Msg := '''###ERROR:DATA PROVIDED EXCEEDS THE MAXIMUM DATA SIZE AS DEFINED IN THE MASTERS FOR FIELD:' ||
                           m_Rec_Columns(i) || ' FOR ' || p_Tran_Type ||
                           ' TRANSACTION. MAX SIZE DEFINED  <= ' || m_Size || '';
              m_Str     := 'UPDATE ' || m_Tran_Table || '
                        SET Sz_Errmsg = Sz_Errmsg ||' ||
                           m_Err_Msg || ''' WHERE ' || m_Size || '<Length(' ||
                           m_Rec_Columns(i) || ') and SZ_FILENAME=''' ||
                           m_File_Name || '''';
              EXECUTE IMMEDIATE m_Str;
              m_Rowcount    := SQL%ROWCOUNT;
              m_Err_Rec_Cnt := m_Err_Rec_Cnt + m_Rowcount;
            ELSIF (m_Datatype = 'DATE') THEN
              m_Err_Msg := '''###ERROR:DATE IS NOT PROVIDED IN THE DESIRED DATE FORMAT:' ||
                           m_Rec_Columns(i) || ' FOR ' || p_Tran_Type ||
                           ' TRANSACTION. DESIRED DATA TYPE SHOULD BE:' ||
                           m_Datatype || '''';
            
              m_Str := 'UPDATE ' || m_Tran_Table ||
                       ' SET SZ_ERRMSG = SZ_ERRMSG||' || m_Err_Msg ||
                       ' WHERE F_DATE(' || m_Rec_Columns(i) ||
                       ')=0 and SZ_FILENAME=''' || m_File_Name || '''';
            
              EXECUTE IMMEDIATE m_Str;
              m_Rowcount    := SQL%ROWCOUNT;
              m_Err_Rec_Cnt := m_Err_Rec_Cnt + m_Rowcount;
            ELSIF (m_Datatype IN ('CHAR', 'VARCHAR2')) THEN
              m_Err_Msg := '''###ERROR:DATA PROVIDED EXCEEDS THE MAXIMUM DATA SIZE AS DEFINED IN THE MASTERS FOR FIELD:' ||
                           m_Rec_Columns(i) || ' FOR ' || p_Tran_Type ||
                           ' TRANSACTION. MAX SIZE DEFINED  <= ' || m_Size || '';
            
              m_Str := 'UPDATE ' || m_Tran_Table || '
                        SET Sz_Errmsg = Sz_Errmsg ||' ||
                       m_Err_Msg || ''' WHERE ' || m_Size || '<Length(' ||
                       m_Rec_Columns(i) || ') and SZ_FILENAME=''' ||
                       m_File_Name || '''';
            
              EXECUTE IMMEDIATE m_Str;
              m_Rowcount    := SQL%ROWCOUNT;
              m_Err_Rec_Cnt := m_Err_Rec_Cnt + m_Rowcount;
            END IF;
          END IF;
        END LOOP;
      
        --getting count for perticular transaction table
        m_Str := 'select count(1) from ' || m_Tran_Table ||
                 ' where Sz_Org_Code=''' || p_Org_Code ||
                 ''' and Sz_Filename=''' || m_File_Name ||
                 ''' and Sz_Errmsg is not null';
        EXECUTE IMMEDIATE m_Str
          INTO m_Err_Cnt;
      
        IF m_Cnt = m_Err_Cnt THEN
          UPDATE t_Lms_Bulk_Tran_Details a
             SET a.c_Maker_Status = 'R',
                 a.Dt_Lastupdated = To_Date(To_Char(Trunc(Fun_Getbusinessdate(p_Org_Code)) || ' ' ||
                                                    To_Char(SYSDATE,
                                                            'HH12:MI:SS AM')),
                                            'DD/MM/RRRR HH12:MI:SS AM')
          -- a.Dt_Lastupdated = Trunc(Fun_Getbusinessdate(p_Org_Code))
           WHERE a.Sz_Org_Code = p_Org_Code
             AND a.Sz_Transaction_Type = p_Tran_Type
             AND a.Sz_File_Name = m_File_Name
             AND a.c_Maker_Status = 'O';
        ELSE
          UPDATE t_Lms_Bulk_Tran_Details a
             SET a.c_Maker_Status = 'V', --validation process
                 a.Dt_Lastupdated = To_Date(To_Char(Trunc(Fun_Getbusinessdate(p_Org_Code)) || ' ' ||
                                                    To_Char(SYSDATE,
                                                            'HH12:MI:SS AM')),
                                            'DD/MM/RRRR HH12:MI:SS AM')
          --a.Dt_Lastupdated = Trunc(Fun_Getbusinessdate(p_Org_Code))
           WHERE a.Sz_Org_Code = p_Org_Code
             AND a.Sz_Transaction_Type = p_Tran_Type
             AND a.Sz_File_Name = m_File_Name
             AND a.c_Maker_Status = 'O';
        END IF;
        --end
      
        IF m_Err_Rec_Cnt > 0 THEN
          Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Level_Err_Insert(p_Org_Code   => p_Org_Code,
                                                               p_Columns    => m_Colname1,
                                                               p_Tran_Type  => p_Tran_Type,
                                                               p_Tran_Table => m_Tran_Table,
                                                               p_File_Name  => m_File_Name,
                                                               p_Level      => 'LEVEL-1',
                                                               p_Retmsg     => m_Retmsg);
        
          IF m_Retmsg <> 'T' THEN
            RAISE Err_Level1_Insert;
          END IF;
        END IF;
      END LOOP;
    
      ----CALL LEVEL1 VALIDATIONS
      IF p_Tran_Type = 'DRE' AND m_Err_Cnt=0  THEN
      Prc_Lms_Bulk_Dre_level1(p_Org_Code      => p_Org_Code,
                              p_File_Name     => m_File_Name,
                              p_Business_Date => TRUNC(Fun_Getbusinessdate(p_Org_Code)),
                              p_Outstr        => m_Retmsg);
      IF m_Retmsg <> 'T' THEN
        RAISE Err_Level1_Insert;
      END IF;
      ELSIF p_Tran_Type = 'RESCHEDULE' AND m_Err_Cnt=0  THEN
        Prc_Lms_Bulk_Resch_Level1(p_Org_Code      => p_Org_Code,
                                  p_File_Name     => m_File_Name,
                                  p_Business_Date => Trunc(Fun_Getbusinessdate(p_Org_Code)),
                                  p_Outstr        => m_Retmsg);
        IF m_Retmsg <> 'T' THEN
          RAISE Err_Level1_Insert;
        END IF;
      END IF;
      m_Str := 'SELECT COUNT(1)
            FROM ' || m_Tran_Table ||
               ' WHERE Sz_Org_Code =''' || p_Org_Code || '''
             AND Sz_Filename =''' || m_File_Name || '''';
      EXECUTE IMMEDIATE m_Str
        INTO m_Tot_Cnt;
      m_Str := 'SELECT COUNT(1)
            FROM ' || m_Tran_Table ||
               ' WHERE Sz_Org_Code =''' || p_Org_Code || '''
             AND Sz_Filename =''' || m_File_Name || '''
             AND Sz_Errmsg IS not NULL';
      EXECUTE IMMEDIATE m_Str
        INTO m_err_Cnt;
      IF m_Tot_Cnt = m_err_Cnt THEN
        UPDATE t_Lms_Bulk_Tran_Details t
           SET t.c_Batch_Status   = 'C',
               t.c_Checker_Status = 'C',
               t.c_Maker_Status   = 'R'
         WHERE t.Sz_Org_Code = p_Org_Code
           AND t.Sz_Transaction_Type = p_Tran_Type
           AND t.Sz_File_Name = m_File_Name;
      END IF;
    END IF;
  
  EXCEPTION
    WHEN Err_Level1_Insert THEN
      m_Err_Msg := 'Error occured for LEVEL-1:' || p_Tran_Type || '::' ||
                   m_Retmsg;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Level_Err_Insert',
                                                    p_Errmsg   => m_Err_Msg);
    
    WHEN OTHERS THEN
      m_Err_Msg := 'Error occured:' || p_Tran_Type ||
                   ' transaction of column:' || m_Colname || '::' ||
                   Substr(SQLERRM, 1, 1000);
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Level1_Validation',
                                                    p_Errmsg   => m_Err_Msg);
    
  END Prc_Lms_Bulk_Level1_Validation;

  PROCEDURE Prc_Lms_Bulk_Level_Err_Insert(p_Org_Code   IN VARCHAR2,
                                          p_Columns    IN VARCHAR2,
                                          p_Tran_Type  IN VARCHAR2,
                                          p_Tran_Table IN VARCHAR2,
                                          p_File_Name  IN VARCHAR2,
                                          p_Level      IN VARCHAR2,
                                          p_Retmsg     OUT VARCHAR2) IS
    Arr_Err_Msg_Log  Array_Error_Msg := Array_Error_Msg();
    Arr_Err_Line_Log Array_Error_Line := Array_Error_Line();
    m_Srno           NUMBER := 0;
    m_Str            VARCHAR2(4000);
    Err_Log_File EXCEPTION;
    m_Retmsg VARCHAR2(4000);
  BEGIN
    IF p_Level = 'LEVEL-1' THEN
      m_Str := 'SELECT Sz_Errmsg,' || p_Columns || '
      FROM ' || p_Tran_Table || '
   WHERE Sz_Errmsg IS NOT NULL
   AND SZ_ORG_CODE=''' || p_Org_Code || '''
   AND SZ_FILENAME= ''' || p_File_Name || '''';
    ELSIF p_Level = 'LEVEL-2' THEN
      m_Str := 'SELECT Sz_Stage2_Err,' || p_Columns || '
      FROM ' || p_Tran_Table || '
   WHERE Sz_Stage2_Err IS NOT NULL
   AND SZ_ORG_CODE=''' || p_Org_Code || '''
   AND SZ_FILENAME= ''' || p_File_Name || '''';
    END IF;
  
    EXECUTE IMMEDIATE m_Str BULK COLLECT
      INTO Arr_Err_Msg_Log, Arr_Err_Line_Log;
  
    BEGIN
      SELECT Nvl(MAX(i_Sr_No), 0) + 1
        INTO m_Srno
        FROM t_Lms_Bulk_Level_Error_Log;
    EXCEPTION
      WHEN OTHERS THEN
        m_Srno := 1;
    END;
    FORALL k IN 1 .. Arr_Err_Msg_Log.Count
      INSERT INTO t_Lms_Bulk_Level_Error_Log
        (i_Sr_No,
         Sz_Org_Code,
         Sz_Tran_Type,
         Sz_Level_Name,
         Sz_File_Name,
         Sz_Error_Msg,
         Sz_Error_Line,
         c_Errfile_Yn)
      VALUES
        (m_Srno,
         p_Org_Code,
         p_Tran_Type,
         p_Level,
         p_File_Name,
         Arr_Err_Msg_Log(k),
         Arr_Err_Line_Log(k),
         'N');
  
    Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Level_Err_File(p_Org_Code  => p_Org_Code,
                                                       p_Tran_Type => p_Tran_Type,
                                                       p_File_Name => p_File_Name,
                                                       p_Level     => p_Level,
                                                       p_Retmsg    => m_Retmsg);
    IF m_Retmsg <> 'T' THEN
      RAISE Err_Log_File;
    END IF;
    p_Retmsg := 'T';
  EXCEPTION
    WHEN Err_Log_File THEN
      m_Retmsg := 'Error Occured in Reschedule process LEVEL::' || p_Level ||
                  '::for file name:' || p_File_Name || ':' || m_Retmsg;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Level_Err_File',
                                                    p_Errmsg   => m_Retmsg);
    
    WHEN OTHERS THEN
      p_Retmsg := Substr(SQLERRM, 1, 1000);
  END Prc_Lms_Bulk_Level_Err_Insert;

  PROCEDURE Prc_Lms_Bulk_Level_Err_File(p_Org_Code  IN VARCHAR2,
                                        p_Tran_Type IN VARCHAR2,
                                        p_File_Name IN VARCHAR2,
                                        p_Level     IN VARCHAR2,
                                        p_Retmsg    OUT VARCHAR2) IS
    m_Err_Dir   m_Lms_Condition_Parameter.Sz_Value%TYPE;
    m_Cnt       NUMBER := 0;
    m_Fname     VARCHAR2(4000);
    m_File      Utl_File.File_Type;
    l_Row       VARCHAR2(32767);
    l_Buffer    VARCHAR2(32767);
    l_Delimiter CHAR(1) := Chr(10);
    TYPE Type_Rec_Err IS TABLE OF VARCHAR2(4000);
    m_Rec_Err_Msg  Type_Rec_Err := Type_Rec_Err();
    m_Rec_Err_Line Type_Rec_Err := Type_Rec_Err();
    TYPE Typ_Mig_Err IS TABLE OF VARCHAR2(4000);
    m_Rec_Rowid Typ_Mig_Err := Typ_Mig_Err();
  BEGIN
    SELECT m.Sz_Value
       INTO m_Err_Dir
      FROM m_Lms_Condition_Parameter m
     WHERE m.Sz_Org_Code = p_Org_Code
       AND m.Sz_Condition = 'LMS_BULK_ERR_PATH';
  
    SELECT COUNT(1)
      INTO m_Cnt
      FROM (SELECT To_Char(k.Sz_Error_Msg) Err_Msg,
                   To_Char(k.Sz_Error_Line) Err_Line
              FROM t_Lms_Bulk_Level_Error_Log k
             WHERE k.Sz_Org_Code = p_Org_Code
               AND k.Sz_Tran_Type = p_Tran_Type
               AND k.Sz_File_Name = p_File_Name
               AND k.Sz_Level_Name = p_Level
               AND c_Errfile_Yn = 'N');
  
    IF m_Cnt > 0 THEN
      m_Fname := 'ERR_' || p_Level || '_' || p_File_Name || '_' ||
                 To_Char(SYSDATE, 'DDMONYYYY hh24:mi:ss') || '.csv';
      m_File  := Utl_File.Fopen(m_Err_Dir, m_Fname, 'W', 32000);
    
      SELECT To_Char(k.Sz_Error_Msg) Err_Msg,
             To_Char(k.Sz_Error_Line) Err_Line,
             ROWID BULK COLLECT
        INTO m_Rec_Err_Msg, m_Rec_Err_Line, m_Rec_Rowid
        FROM t_Lms_Bulk_Level_Error_Log k
       WHERE k.Sz_Org_Code = p_Org_Code
         AND k.Sz_Tran_Type = p_Tran_Type
         AND k.Sz_File_Name = p_File_Name
         AND k.Sz_Level_Name = p_Level
         AND c_Errfile_Yn = 'N';
    
      FOR k IN 1 .. m_Rec_Rowid.Count LOOP
        l_Row := p_Tran_Type || '::::' || m_Rec_Err_Msg(k) || '::::' ||
                 m_Rec_Err_Line(k) || l_Delimiter;
        IF Length(l_Buffer) + Length(l_Row) > 32700 THEN
          Utl_File.Put_Line(m_File, l_Buffer);
          l_Buffer := l_Row;
        ELSE
          l_Buffer := l_Buffer || l_Row;
        END IF;
      
        UPDATE t_Lms_Bulk_Level_Error_Log l
           SET l.c_Errfile_Yn = 'Y'
         WHERE l.Rowid = m_Rec_Rowid(k);
      END LOOP;
    
      Utl_File.Put_Line(m_File, l_Buffer);
      Utl_File.Fclose(m_File);
    END IF;
    p_Retmsg := 'T';
  EXCEPTION
    WHEN OTHERS THEN
      p_Retmsg := Substr(SQLERRM, 1, 1000);
  END Prc_Lms_Bulk_Level_Err_File;

  /*This proceudre is used for checking the duplicate file name,duplicate records*/
  PROCEDURE Prc_Lms_Bulk_Duplicate(p_Org_Code  IN VARCHAR2,
                                   p_Tran_Type IN VARCHAR2,
                                   p_File_Name IN VARCHAR2,
                                   p_Outstr    OUT VARCHAR2) IS
  
    m_Tran_Table m_Lms_Bulk_Header.Sz_Tran_Table%TYPE;
    m_Str        VARCHAR2(4000);
    --m_File_Cnt   NUMBER := 0;
    --m_Dup_Fl_Cnt      NUMBER := 0;
    --m_Loan_Cnt        NUMBER := 0;
    m_Err_Msg  VARCHAR2(4000);
    m_File_Str VARCHAR2(4000);
    -- m_Loan_Account_No t_Lms_Loan_Account.Sz_Loan_Account_No%TYPE;
    m_Str_Dup VARCHAR2(4000);
  BEGIN
    SELECT m.Sz_Tran_Table
      INTO m_Tran_Table
      FROM m_Lms_Bulk_Header m
     WHERE m.Sz_Org_Code = p_Org_Code
       AND m.Sz_Transaction_Type = p_Tran_Type;
  
    IF p_File_Name NOT LIKE '%_i.%' THEN
    
      /*this code is used to check compare loanaccount string in different file*/
     /* m_Str_Dup := 'WITH a AS
       (SELECT Listagg(t.Sz_Loan_Account_No, '','') Within GROUP(ORDER BY t.Rowid) Sz_Lan1,
               Listagg(t.Sz_Filename, '','') Within GROUP(ORDER BY t.Rowid) Sz_File1
          FROM ' || m_Tran_Table || ' t
         WHERE t.Sz_Org_Code =''' || p_Org_Code || '''
           AND t.Sz_Filename <>''' || p_File_Name || '''
         GROUP BY Sz_Filename),
      b AS
       (SELECT Listagg(t.Sz_Loan_Account_No, '','') Within GROUP(ORDER BY t.Rowid) Sz_Lan2,
               Listagg(t.Sz_Filename, '','') Within GROUP(ORDER BY t.Rowid) Sz_File2
          FROM  ' || m_Tran_Table || ' t
         WHERE t.Sz_Org_Code = ''' || p_Org_Code || '''
           AND t.Sz_Filename = ''' || p_File_Name || ''')
      SELECT Nvl(Listagg(k.Sz_Filename, '','') Within
                 GROUP(ORDER BY k.Sz_Filename),
                 ''1'') Sz_Filename
        FROM (SELECT a.Sz_Lan1,
                     a.Sz_File1,
                     b.Sz_Lan2,
                     b.Sz_File2,
                     Regexp_Substr(a.Sz_File1, ''[^,]+'', 1) Sz_Filename
                FROM a, b
               WHERE a.Sz_Lan1 = b.Sz_Lan2
                 AND a.Sz_File1 <> b.Sz_File2) k';*/
        ---ISSUE FIXED 145258         
        m_Str_Dup := 'WITH a AS
       (SELECT Listagg(t.Sz_Loan_Account_No, '','') Within GROUP(ORDER BY t.Rowid) Sz_Lan1,
               Listagg(t.Sz_Filename, '','') Within GROUP(ORDER BY t.Rowid) Sz_File1
          FROM ' || m_Tran_Table || ' t,t_Lms_Bulk_Tran_Details d




         WHERE t.Sz_Org_Code = d.Sz_Org_Code
        AND d.c_Maker_Status IN (''M'', ''P'')
        and d.c_checker_status not in (''C'',''R'')
        AND t.Sz_Filename = d.Sz_File_Name
        AND t.Sz_Org_Code =''' || p_Org_Code || '''
           AND t.Sz_Filename <>''' || p_File_Name || '''
         GROUP BY Sz_Filename),
      b AS
       (SELECT Listagg(t.Sz_Loan_Account_No, '','') Within GROUP(ORDER BY t.Rowid) Sz_Lan2,
               ''' || p_File_Name || ''' Sz_File2
          FROM  ' || m_Tran_Table || ' t
         WHERE t.Sz_Org_Code = ''' || p_Org_Code || '''
           AND t.Sz_Filename = ''' || p_File_Name || ''')
      SELECT Nvl(Listagg(k.Sz_Filename, '','') Within
                 GROUP(ORDER BY k.Sz_Filename),
                 ''1'') Sz_Filename
        FROM (SELECT a.Sz_Lan1,
                     a.Sz_File1,
                     b.Sz_Lan2,
                     b.Sz_File2,
                     Regexp_Substr(a.Sz_File1, ''[^,]+'', 1) Sz_Filename FROM a, b
               WHERE a.Sz_Lan1 = b.Sz_Lan2
                 AND a.Sz_File1 <> b.Sz_File2) k';
        ---END ISSUE FIXED 145258               
    
      EXECUTE IMMEDIATE m_Str_Dup
        INTO m_File_Str;
    
      IF m_File_Str <> '1' THEN
        m_Err_Msg := '''###ERROR:Duplicate Loan Account Records found in other file:' ||
                     m_File_Str ||
                     ' ,If you still want to upload this file append _i at the end of file name then no validation will be performed for file name''';
        /*  m_Err_Msg := '''###ERROR:Duplicate Loan Account Records found in other file:' ||
        m_File_Str || '''';*/
        m_Str := 'UPDATE ' || m_Tran_Table ||
                 ' SET SZ_ERRMSG = SZ_ERRMSG||' || m_Err_Msg ||
                 ' WHERE
                 Sz_Org_Code=''' || p_Org_Code ||
                 ''' AND SZ_FILENAME=''' || p_File_Name || '''';
        EXECUTE IMMEDIATE m_Str;
        /*  p_Outstr := 'Duplicate Loan Account Records found in other file:' ||
                            m_File_Str||' ,If you still want to upload this file append _i at the end of file name then no validation will be performed for file name';
        */
        p_Outstr := '11';
      ELSE
    p_Outstr := NULL;
      END IF;
     ELSE
       p_Outstr := NULL;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      p_Outstr  := NULL;
      m_Err_Msg := 'Error occured for Transaction Type:' || p_Tran_Type ||
                   ' and file name:' || p_File_Name || ' table:' ||
                   m_Tran_Table || '::' || Substr(SQLERRM, 1, 1000);
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Duplicate',
                                                    p_Errmsg   => m_Err_Msg);
    
  END Prc_Lms_Bulk_Duplicate;

  PROCEDURE Prc_Lms_Bulk_Error_Log(p_Org_Code IN VARCHAR2,
                                   p_Object   IN VARCHAR2,
                                   p_Errmsg   IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    m_Srno NUMBER := 0;
  BEGIN
    /*DELETE FROM t_Lms_Bulk_Error_Log t
    WHERE t.Sz_Object = 'Prc_Lms_Bulk_Gen_File::LOG';*/
  
    BEGIN
      SELECT Nvl(MAX(i_Seqno), 0) + 1
        INTO m_Srno
        FROM t_Lms_Bulk_Error_Log
       WHERE Sz_Org_Code = p_Org_Code;
    EXCEPTION
      WHEN OTHERS THEN
        m_Srno := 1;
    END;
  
    INSERT INTO t_Lms_Bulk_Error_Log
      (Sz_Org_Code, i_Seqno, Sz_Object, Sz_Errmsg)
    VALUES
      (p_Org_Code, m_Srno, p_Object, p_Errmsg);
    COMMIT;
  
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END Prc_Lms_Bulk_Error_Log;

  -----Reschedule execution procedures started
  PROCEDURE Prc_Lms_Bulk_Resch(p_Org_Code IN VARCHAR2,
                               
                               p_File_Name     IN VARCHAR2,
                               p_Business_Date IN DATE,
                               p_Outstr        OUT VARCHAR2) IS
    TYPE Type_Resch IS TABLE OF t_Lms_Genbulk_Reschedule%ROWTYPE;
    Rec_Resch Type_Resch := Type_Resch();
    m_Retstr  VARCHAR2(4000);
    Err_Resch_Setup EXCEPTION;
    Err_Resch_Val EXCEPTION;
    Err_Level2_Insert EXCEPTION;
    TYPE Type_Col IS TABLE OF VARCHAR2(4000);
    m_Rec_Columns   Type_Col := Type_Col();
    m_Colname       VARCHAR2(4000);
    m_Colname1      VARCHAR2(4000);
    m_Err2_Cnt      NUMBER := 0;
    m_Change_Factor VARCHAR2(50);
    m_Xml           VARCHAR2(4000);
  BEGIN
    Prc_Lms_Bulk_Setup_Val(p_Org_Code  => p_Org_Code,
                           p_Filename  => p_File_Name,
                           p_Tran_Type => 'RESCHEDULE',
                           p_Retmsg    => m_Retstr);
  
    IF m_Retstr <> 'T' THEN
      RAISE Err_Resch_Setup;
    END IF;
  
    SELECT * BULK COLLECT

      INTO Rec_Resch
      FROM t_Lms_Genbulk_Reschedule t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Filename = p_File_Name
       AND t.Sz_Errmsg IS NULL
       AND t.Sz_Stage2_Err IS NULL;
  
    IF Rec_Resch.Count > 0 THEN
      FOR i IN Rec_Resch.First .. Rec_Resch.Last LOOP
        SELECT Decode(Rec_Resch(i).c_Change_Factor,
                      'I',
                      'E',
                      Rec_Resch(i).c_Change_Factor) Fac
          INTO m_Change_Factor
          FROM Dual;
        Prc_Lms_Bulk_Resch_Val(p_Org_Code        => p_Org_Code,
                               p_Filename        => p_File_Name,
                               p_Loan_Account_No => Rec_Resch(i)
                                                    .Sz_Loan_Account_No,
                               p_Tranche_No      => Rec_Resch(i).i_Tranche_No,
                               p_Srno            => Rec_Resch(i).Row_Srno,
                               p_Repay_Freq      => Rec_Resch(i).c_Repay_Freq,
                               p_Change_Factor   => m_Change_Factor,
                               
                               p_Cycleday        => Rec_Resch(i).i_Cycleday,
                               p_Installment_Amt => Rec_Resch(i)
                                                    .f_Installment_Amt,
                               p_Tenor           => Rec_Resch(i).i_Tenor,
                               p_Interestrate    => Rec_Resch(i)
                                                    .f_Interestrate,
                               p_Remarks         => Rec_Resch(i).Sz_Remarks,
                               p_Offset          => Rec_Resch(i)
                                                    .f_Offset_Rate,
                               p_Reason          => Rec_Resch(i).Sz_Reason,
                               p_Equated_Prin    => To_Number(Rec_Resch(i)
                                                              .c_Prin_Repay_Freq),
                               p_Business_Date   => p_Business_Date,
                               p_Userid          => Rec_Resch(i).Sz_Userid,
                               p_eff_inst_dt     => Rec_Resch(i)
                                                    .DT_EFFECTIVE_INST_DATE, -- Added for Reschedule on Partially Disbursed Cases
                               p_Retmsg          => m_Retstr);
        IF m_Retstr <> 'T' THEN
          RAISE Err_Resch_Val;
        END IF;
      END LOOP;
    END IF;
  
    ---LEVEL 2 ERROR LOG
    SELECT COUNT(1)
      INTO m_Err2_Cnt
      FROM t_Lms_Genbulk_Reschedule r
     WHERE r.Sz_Org_Code = p_Org_Code
       AND r.Sz_Filename = p_File_Name
       AND r.Sz_Stage2_Err IS NOT NULL;
  
    IF m_Err2_Cnt > 0 THEN
    
      SELECT TRIM(Ut.Column_Name) Column_Name BULK COLLECT
        INTO m_Rec_Columns
        FROM User_Tab_Columns Ut
       WHERE Ut.Table_Name = 'T_LMS_GENBULK_RESCHEDULE'
         AND Ut.Column_Name NOT IN ('SZ_STAGE2_ERR',
                                    'SZ_ERRMSG',
                                    'SZ_FILENAME',
                                    'DT_LASTUPDATED',
                                    'SZ_USERID',
                                    'SZ_ORG_CODE')
       ORDER BY Ut.Column_Id;
    
      FOR i IN m_Rec_Columns.First .. m_Rec_Columns.Last LOOP
        m_Colname  := m_Rec_Columns(i);
        m_Colname1 := m_Colname1 || '$' || m_Colname;
        m_Colname1 := TRIM(Leading '$' FROM m_Colname1);
        m_Colname1 := REPLACE(m_Colname1, '$', '||'',''||');
      END LOOP;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Level_Err_Insert(p_Org_Code   => p_Org_Code,
                                                           p_Columns    => m_Colname1,
                                                           p_Tran_Type  => 'RESCHEDULE',
                                                           p_Tran_Table => 'T_LMS_GENBULK_RESCHEDULE',
                                                           p_File_Name  => p_File_Name,
                                                           p_Level      => 'LEVEL-2',
                                                           p_Retmsg     => m_Retstr);
    
      IF m_Retstr <> 'T' THEN
        RAISE Err_Level2_Insert;
      END IF;
    END IF;
    --END LEVEL 2 ERROR LOG
    p_Outstr := 'T';
  EXCEPTION
    WHEN Err_Resch_Setup THEN
      p_Outstr := m_Retstr;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Resch_Setup_Val',
                                                    p_Errmsg   => m_Retstr);
    
    WHEN Err_Resch_Val THEN
      p_Outstr := m_Retstr;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Resch_Val',
                                                    p_Errmsg   => m_Retstr);
    
    WHEN Err_Level2_Insert THEN
      p_Outstr := '-101';
      m_Retstr := 'Error occured for LEVEL-2 RESCHEDULE::' || m_Retstr;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Level_Err_Insert',
                                                    p_Errmsg   => m_Retstr);
    
    WHEN OTHERS THEN
      p_Outstr := 'Error Occured in Reschedule process for file name:' ||
                  p_File_Name || ':' || Substr(SQLERRM, 1, 2000);
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Resch',
                                                    p_Errmsg   => p_Outstr);
    
  END Prc_Lms_Bulk_Resch;
  --3
  /*PROCEDURE Prc_Lms_Bulk_Resch_Setup_Val(p_Org_Code VARCHAR2,
                                         p_Filename IN VARCHAR2,
                                         p_Retmsg   OUT VARCHAR2) IS
    m_Retmsg VARCHAR2(4000);
  BEGIN
    UPDATE t_Lms_Genbulk_Reschedule t
       SET t.Sz_Stage2_Err = NULL
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Filename = p_Filename;
    ----lookups
    m_Retmsg := '###ERROR:Repayment Frequency (c_Repay_Freq) not matched with Lookups:REPAYMENT_FREQUENCY';
    UPDATE t_Lms_Genbulk_Reschedule t
       SET Sz_Stage2_Err = Sz_Stage2_Err || m_Retmsg
     WHERE NOT EXISTS (SELECT v.Sz_Lookup_Code
              FROM m_Lms_Lookup v
             WHERE v.Sz_Org_Code = p_Org_Code
               AND Sz_Lookup_Type_Code = 'REPAYMENT_FREQUENCY'
               AND v.Sz_Lookup_Code = t.c_Repay_Freq)
       AND t.Sz_Errmsg IS NULL
       AND t.Sz_Filename = p_Filename;
  
    m_Retmsg := '###ERROR:Reason (SZ_REASON) not matched with Lookup:V_LMS_LOOKUP_RESCHEDULE_REASON';
    UPDATE t_Lms_Genbulk_Reschedule t
       SET Sz_Stage2_Err = Sz_Stage2_Err || m_Retmsg
     WHERE NOT EXISTS (SELECT v.Code
              FROM v_Lms_Lookup_Reschedule_Reason v
             WHERE v.Sz_Org_Code = p_Org_Code
               AND v.Code = t.Sz_Reason)
       AND t.Sz_Errmsg IS NULL
       AND t.Sz_Filename = p_Filename;
  
    --FIXED VALUES
    m_Retmsg := '###ERROR:WHAT TO CALCULATE(C_CHANGE_FACTOR) not matched with Fixed Values:Installment-I,Tenor-T';
    UPDATE t_Lms_Genbulk_Reschedule t
       SET Sz_Stage2_Err = Sz_Stage2_Err || m_Retmsg
     WHERE Sz_Org_Code = p_Org_Code
       AND c_Change_Factor NOT IN ('I', 'T')
       AND t.Sz_Errmsg IS NULL
       AND t.Sz_Filename = p_Filename;
  
    --master
    m_Retmsg := '###ERROR:CYCLE DATE(I_CYCLEDAY) not matched with Master Values:';
    UPDATE t_Lms_Genbulk_Reschedule k
       SET Sz_Stage2_Err = Sz_Stage2_Err || m_Retmsg ||
                           (SELECT Listagg(Cd, ',') Within GROUP(ORDER BY Cd)
                              FROM (SELECT DISTINCT t.Icycday Cd
                                      FROM TABLE(Fn_Evlbilngcyc(p_Org_Code,
                                                                k.Sz_Loan_Account_No)) t))
     WHERE Sz_Org_Code = p_Org_Code
       AND i_Cycleday IS NOT NULL
       AND k.Sz_Errmsg IS NULL
       AND k.Sz_Filename = p_Filename
       AND NOT EXISTS
     (SELECT DISTINCT t.Icycday Cd
              FROM TABLE(Fn_Evlbilngcyc(p_Org_Code, k.Sz_Loan_Account_No)) t
             WHERE t.Icycday = k.i_Cycleday);
  
    p_Retmsg := 'T';
  EXCEPTION
    WHEN OTHERS THEN
      p_Retmsg := 'Error Occured in Setup for Reschedule and file name:' ||
                  p_Filename || ':' || Substr(SQLERRM, 1, 2000);
  END Prc_Lms_Bulk_Resch_Setup_Val;*/

  --4
  PROCEDURE Prc_Lms_Bulk_Resch_Val(p_Org_Code        VARCHAR2,
                                   p_Filename        IN VARCHAR2,
                                   p_Loan_Account_No VARCHAR2,
                                   p_Tranche_No      VARCHAR2,
                                   p_Srno            NUMBER,
                                   p_Repay_Freq      NUMBER,
                                   
                                   p_Change_Factor   CHAR,
                                   p_Cycleday        NUMBER,
                                   p_Installment_Amt NUMBER,
                                   p_Tenor           NUMBER,
                                   p_Interestrate    NUMBER,
                                   p_Remarks         VARCHAR2,
                                   p_Offset          NUMBER,
                                   p_Reason          VARCHAR2,
                                   p_Equated_Prin    NUMBER,
                                   p_Business_Date   DATE,
                                   p_Userid          IN VARCHAR2 DEFAULT 'SYSADMIN',
                                   p_Level_Flag      IN VARCHAR2 DEFAULT NULL,
                                   p_eff_inst_dt     IN DATE, -- Added for Reschedule on Partially Disbursed Cases
                                   p_Retmsg          OUT VARCHAR2) IS
    m_Old_Repfreq  t_Lms_Loan_Account.c_Repay_Freq%TYPE;
    m_Accnt_Status t_Lms_Loan_Account.c_Account_Status%TYPE;
    m_Add_Sts      t_Lms_Loan_Account.c_Additional_Status%TYPE;
    m_Final_Disb   t_Lms_Loan_Account.c_Final_Disb_Yn%TYPE;
    m_Cycle_Day    t_Lms_Loan_Account.i_Cycleday%TYPE;
    m_Portfolio    t_Lms_Loan_Account.Sz_Portfolio_Code%TYPE;
    m_Retmsg       VARCHAR2(4000);
    Mf_Count       NUMBER := 0;
    m_Bal_Tenor    NUMBER := 0;
    m_New_Int_Rate t_Lms_Tranche_Sch_Param.f_Interestrate%TYPE;
    m_Balloon_Yn   CHAR(1);
    m_Flagretrage  CHAR(1);
    m_Total_Due    NUMBER := 0;
    --p_Return_Msg   VARCHAR2(4000);
    m_Tenor        VARCHAR2(4000) := p_Tenor; --NUMBER := 0;
    m_Emi          VARCHAR2(4000); --NUMBER := 0;
    m_Xml_Data     CLOB; --VARCHAR2(4000);
    m_Product_Code t_Lms_Product_Dtls.Sz_Product_Code%TYPE;
    m_Interestrate NUMBER := p_Interestrate;
    m_Proc_Retmsg  VARCHAR2(4000);
    Err_Emi_Tenor_Cal EXCEPTION;
    Err_Amortz_Param EXCEPTION;
    Err_Reschedule_Req EXCEPTION;
    m_Validyn          VARCHAR2(100);
    m_Errormsg         VARCHAR2(4000);
    m_Errorval         VARCHAR2(4000);
    m_Skipclob         CLOB;
    m_Stepclob         CLOB;
    m_Ballonclob       CLOB;
    m_Ademiclob        NUMBER := 0;
    m_Variations       VARCHAR2(4000);
    m_Ballonpay_Amount NUMBER := 0;
    m_Trantype         VARCHAR2(4000);
    m_Tranhead         VARCHAR2(4000);
    m_Osamt            VARCHAR2(4000); --NUMBER := 0;
    m_Taxamt           VARCHAR2(4000); --NUMBER := 0;
    m_Tranche_No       VARCHAR2(4000) := p_Tranche_No;
    m_Waive_Amount     VARCHAR2(4000);
    m_Due_Amount       VARCHAR2(4000);
    m_Cap_Amount       VARCHAR2(4000);
    --m_Tot_Amount        NUMBER := 0;
    m_Total_Amount      NUMBER := 0;
    m_Bpi_Recovery_Flag VARCHAR2(100);
    m_Bsrno             t_Lms_Balloon_Pay.i_Srno%TYPE;
    m_Bmonth            t_Lms_Balloon_Pay.i_Month_Ballon%TYPE;
    m_Bvalue            t_Lms_Balloon_Pay.f_Ballon_Pay%TYPE;
    m_Badj              t_Lms_Balloon_Pay.f_Ballon_Adj%TYPE;
    m_Min_Tenor         Prd_Mst_Product.Imintenor%TYPE; -- t_Lms_Product_Dtls.i_Min_Tenor%TYPE;
    m_Max_Tenor         Prd_Mst_Product.Imaxtenor%TYPE; --t_Lms_Product_Dtls.i_Max_Tenor%TYPE;
    m_Min_Inst_Amt      Prd_Mst_Product.Fmininstallment%TYPE; --t_Lms_Product_Dtls.f_Min_Inst_Amt%TYPE;
    m_Max_Inst_Amt      Prd_Mst_Product.Fmaxinstallment%TYPE; --t_Lms_Product_Dtls.f_Max_Inst_Amt%TYPE;
    m_Min_Int_Rate      Prd_Mst_Product.Ffloorrate%TYPE; --t_Lms_Product_Dtls.f_Min_Int_Rate%TYPE;
    m_Locking_Period    NUMBER := 0;
    m_Max_Intrate       Prd_Mst_Product.Fceilrate%TYPE; --Prd_Vew_Product.f_Pricing_Fix_Max_Int_Rate%TYPE;
    m_Min_Intrate       Prd_Vew_Product.f_Pricing_Fix_Min_Int_Rate%TYPE;
  
    --m_Inst_From NUMBER := 0;
    --m_Inst_To   NUMBER := 0;
    --m_Step_Adj  t_Lms_Step_Pay.Sz_Step_Adj%TYPE;
  
    --m_Step_Value    t_Lms_Step_Pay.f_Step_Value%TYPE;
    --m_Skip_Instfrom NUMBER := 0;
    --m_Skip_Instto   NUMBER := 0;
    m_Interest_Type t_Lms_Product_Dtls.c_Interest_Type%TYPE;
  
    m_Index_Code      Prd_Vew_Amort_Portfolio_Xref.Sz_Pricing_Idx_Rate_Code%TYPE;
    m_Index_Rate      Prd_Vew_Amort_Portfolio_Xref.Sz_Pricing_Idx_Rate_Code%TYPE;
    m_Spread_Code     Prd_Vew_Amort_Portfolio_Xref.Sz_Pricing_Idx_Spread_Code%TYPE;
    m_Idx_Spread_Rate Prd_Vew_Amort_Portfolio_Xref.f_Pricing_Idx_Spread_Rate%TYPE;
    m_Max_Offsetrate  Prd_Vew_Amort_Portfolio_Xref.f_Pricing_Idx_Max_Offset%TYPE;
    m_Reterr          VARCHAR2(4000);
    Err_Ext_Resh_Val EXCEPTION;
    m_Old_Interestrate t_Lms_Tranche_Dtls.f_Curr_Interestrate%TYPE;
    m_Old_Freq         t_Lms_Product_Dtls.i_Compounding_Freq%TYPE;
    m_Old_Cycle        t_Lms_Loan_Account.i_Cycleday%TYPE;
    --m_Osamt_Fee        v_Lms_Head_Wise_Due.Osamt%TYPE;
    --m_Event_Chg        NUMBER := 0;
    --m_Event_Tax        NUMBER := 0;
    --m_Return_Msg       VARCHAR2(4000);
    m_Fixed    NUMBER := 0;
    m_Variable NUMBER := 0;
    ----added by APRANSHU
    m_Instlmnt_To   NUMBER := 0;
    m_Next_Instlmnt NUMBER := 0;
    m_Excess_Amt    t_Lms_Loan_Account.f_Excess_Amt%TYPE;
    m_Value         m_Lms_Condition_Parameter.Sz_Value%TYPE;
    m_Change_Factor VARCHAR2(100);
    m_Module        VARCHAR2(4000) := 'RESCHEDULE';
    m_Err_Msg       VARCHAR2(4000);
    --m_Xml           VARCHAR2(4000);
    m_Equated_Prin t_Lms_Product_Dtls.f_Equated_Prin_Frq%TYPE;
    m_Prin_Freq    CHAR(1) := 'N';
    m_Dateofcycle  VARCHAR2(4000);
    m_Lan_Count    NUMBER := 0;
    m_installment_amt NUMBER:=p_Installment_Amt;
    m_Final_Disb_Yn t_Lms_Loan_Account.c_Final_Disb_Yn%TYPE;
    m_eff_inst_dt DATE; -- Added for Reschedule on Partially Disbursed Cases
    m_Tr_Count        NUMBER := 0;
    m_Trl_Count       NUMBER := 0;
    m_repay_freq          t_lms_loan_account.c_repay_freq%type; -- added for bug : 147936
    M_DT_NEXT_INSTALLMENT t_lms_loan_account.dt_next_installment%type; -- added for bug : 147936
  BEGIN
    m_Retmsg := NULL;
    ---Daily Repay Freq Enh 
    SELECT Nvl(Pkg_General_Services.Get_Repayment_Frequency_Code(p_Org_Code        => p_Org_Code,
                                                                 p_Loan_Account_No => p_Loan_Account_No),
               12)
      INTO m_Repay_Freq
      FROM Dual;
    ---ISSUE FIXED 147494
     SELECT COUNT(1)
      INTO m_Lan_Count
      FROM t_Lms_Loan_Account t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Loan_Account_No = p_Loan_Account_No;
    IF m_Lan_Count = 0 AND p_Level_Flag = 'LEVEL1' THEN
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Errmsg = Sz_Errmsg || '###ERROR:Invalid Loan Account Number'


       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Sz_Filename = p_Filename
         AND t.Row_Srno = p_Srno;
      RETURN;
    END IF;
    ---issue fixed 149797 for multitranche
    SELECT COUNT(1)
      INTO m_Tr_Count
      FROM t_Lms_Tranche_Dtls t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Loan_Account_No = p_Loan_Account_No
       AND t.i_Tranche_No = p_Tranche_No;
    IF m_Tr_Count = 0 AND p_Level_Flag = 'LEVEL1' THEN
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Errmsg = Sz_Errmsg || '###ERROR:Invalid Tranche Number'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.i_Tranche_No = p_Tranche_No
         AND t.Sz_Filename = p_Filename
         AND t.Row_Srno = p_Srno;
      RETURN;
    END IF;
    SELECT COUNT(1)
      INTO m_Trl_Count
      FROM t_Lms_Tranche_Dtls t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Loan_Account_No = p_Loan_Account_No
       AND t.i_Tranche_No = p_Tranche_No
       AND Nvl(t.c_Req_Status, 'L') = 'L';
    IF m_Trl_Count = 0 AND p_Level_Flag = 'LEVEL1' THEN
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Errmsg = Sz_Errmsg || '###ERROR:Tranche Number not Active'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.i_Tranche_No = p_Tranche_No
         AND t.Sz_Filename = p_Filename
         AND t.Row_Srno = p_Srno;
      RETURN;
    END IF;
    ---end
    /* Added for Reschedule on Partially Disbursed Cases */
    /* Start - Issue Fix : 147936 */
    If p_Cycleday is null Then
      --IF p_Eff_Inst_Dt IS NULL THEN
        SELECT LA.I_CYCLEDAY
          INTO M_CYCLE_DAY
          FROM t_lms_loan_account la
         WHERE la.sz_org_code = P_Org_Code
           AND la.sz_loan_account_no = p_Loan_Account_No;
      /*ELSE
      m_Cycle_Day := To_Number(To_Char(To_Date(p_Eff_Inst_Dt,
                                               'dd-mm-rrrr'),
                                       'DD'));*/

      End If;
  
    select DT_NEXT_INSTALLMENT
      Into M_DT_NEXT_INSTALLMENT
      from t_lms_loan_account a
     where a.sz_org_code = p_Org_Code
       and a.sz_loan_account_no = p_Loan_Account_No;
    If p_eff_inst_dt is null Then
    
      select a.c_repay_freq
        into m_repay_freq
        from t_lms_loan_account a
       where a.sz_org_code = p_Org_Code
         and a.sz_loan_account_no = p_Loan_Account_No;
      If m_repay_freq = p_Repay_Freq Then
        m_Eff_Inst_Dt := M_DT_NEXT_INSTALLMENT;
      Else
      SELECT decode(p_Repay_Freq,
                    1,
                    add_months(trunc(get_businessdate(p_org_code)), 12),
                    2,
                    add_months(trunc(get_businessdate(p_org_code)), 6),
                    4,
                    add_months(trunc(get_businessdate(p_org_code)), 3),
                    3,
                    add_months(trunc(get_businessdate(p_org_code)), 4),
                    6,
                    add_months(trunc(get_businessdate(p_org_code)), 2),
                    12,
                    add_months(trunc(get_businessdate(p_org_code)), 1),
                    26,
                    trunc(get_businessdate(p_org_code)) + 15,
                    52,
                    trunc(get_businessdate(p_org_code)) + 7,
                    360,---Daily Repay Freq Enh
                    trunc(get_businessdate(p_org_code)) + 1---Daily Repay Freq Enh
                    ) dt_effective_inst
        INTO m_eff_inst_dt
          FROM dual;
      End If;
    
      Begin
        -- Month End as Due Date Enh. 
      m_eff_inst_dt := to_date(NVL(p_Cycleday, M_CYCLE_DAY) || '/' ||
                               to_char(to_date(m_eff_inst_dt, 'dd-mm-rrrr'),


                                       'MM/RRRR'),
                               'DD/MM/RRRR');
        /* Start - Month End as Due Date Enh. */
      Exception
        When Others Then
          m_eff_inst_dt := Last_Day(m_eff_inst_dt);
      End;
      /* End - Month End as Due Date Enh. */
    
       IF m_Eff_Inst_Dt < M_DT_NEXT_INSTALLMENT OR
         (Pkg_Reschedule.Fun_Val_Batch_Days(p_org_code,
                                         p_Loan_Account_No,
                                         '1',
                                         Fun_Getbusinessdate(p_org_code))='Y' AND
         m_Repay_Freq <> 360) Then--ISSUE FIXED 151742,151727 DISCUSSED WITH maithlee--Daily Repay Freq Enh


        SELECT Decode(p_Repay_Freq,
                      1,
                      Add_Months(m_Eff_Inst_Dt, 12),
                      2,
                      Add_Months(m_Eff_Inst_Dt, 6),
                      4,
                      Add_Months(m_Eff_Inst_Dt, 3),
                      3,
                      Add_Months(m_Eff_Inst_Dt, 4),
                      6,
                      Add_Months(m_Eff_Inst_Dt, 2),
                      12,
                      Add_Months(m_Eff_Inst_Dt, 1),
                      26,
                      m_Eff_Inst_Dt + 15,
                      52,
                      m_Eff_Inst_Dt + 7,
                      360,---Daily Repay Freq Enh
                      m_Eff_Inst_Dt + 1---Daily Repay Freq Enh
                      ) Dt_Effective_Inst
          INTO m_Eff_Inst_Dt
          FROM dual;
    End If;
    END IF;
    /* End - Issue Fix : 147936 */
    /* End for Reschedule on Partially Disbursed Cases */
    ---screen level validations
    Prc_Resch_Screen_Validations(p_Org_Code        => p_Org_Code,
                                 p_Filename        => p_Filename,
                                 p_Loan_Account_No => p_Loan_Account_No,
                                 p_Tranche_No      => p_Tranche_No,
                                 p_Srno            => p_Srno,
                                 p_Repay_Freq      => p_Repay_Freq,
                                 p_Change_Factor   => p_Change_Factor,
                                 p_Cycleday        => NVL(p_Cycleday,
                                                          M_CYCLE_DAY), -- Issue Fix : 147936
                                 p_Installment_Amt => p_Installment_Amt,
                                 p_Tenor           => p_Tenor,
                                 p_Interestrate    => p_Interestrate,
                                 p_Remarks         => p_Remarks,
                                 p_Offset          => p_Offset,
                                 p_Reason          => p_Reason,
                                 p_Equated_Prin    => p_Equated_Prin,
                                 p_Business_Date   => p_Business_Date,
                                 p_Userid          => p_Userid,
                                 p_Level_Flag      => p_Level_Flag,
                                 p_eff_inst_dt     => nvl(p_eff_inst_dt,m_eff_inst_dt), -- Added for Reschedule on Partially Disbursed Cases


                                 p_Retmsg          => m_Retmsg);
  
    IF m_Retmsg = 'T' THEN
      Prc_Lms_Bulk_Resch_Whatifval(p_Org_Code            => p_Org_Code,
                                   p_Filename            => p_Filename,
                                     p_Loan_Account_No => p_Loan_Account_No,
                                     p_Srno            => p_Srno,
                                   p_Repay_Freq          => p_Repay_Freq,
                                   p_Change_Factor       => p_Change_Factor,
                                   p_Cycleday            => NVL(p_Cycleday,
                                                          M_CYCLE_DAY), -- Issue Fix : 147936,
                                   p_Installment_Amt     => m_Installment_Amt,
                                   p_Tenor               => m_Tenor,
                                   p_Interestrate        => p_Interestrate,
                                   p_Remarks             => p_Remarks,
                                   p_Offset              => p_Offset,
                                   p_Reason              => p_Reason,
                                   p_Equated_Prin        => p_Equated_Prin,
                                   p_Business_Date       => p_Business_Date,
                                   p_Userid              => p_Userid,
                                   p_Level_Flag          => p_Level_Flag,
                                   p_Retmsg              => m_Retmsg,
                                   p_Tranche_No          => m_Tranche_No,
  
                                                         p_Trantype        => m_Trantype,
                                                         p_Tranhead        => m_Tranhead,
                                   p_Osamount            => m_Osamt,
                                   p_Waive_Amount        => m_Waive_Amount,
                                   p_Due_Amount          => m_Due_Amount,
                                   p_Cap_Amount          => m_Cap_Amount,
                                   p_Total_Amount        => m_Total_Amount,
                                   p_New_Product         => m_Product_Code,
                                   p_Interest_Rate       => m_Interestrate,
                                   p_Repayment_Prin_Freq => m_Equated_Prin,
                                   p_Variationxml        => m_Xml_Data,
                                   p_Adj_Bpi_Nxt_Inst    => m_Bpi_Recovery_Flag,
                                   p_Interest_Type       => m_Interest_Type,
                                   p_Index_Code          => m_Index_Code,
                                   p_Index_Rate          => m_Index_Rate,
                                   p_Offset_Rate         => m_Max_Offsetrate,
                                   p_Spread_Rate         => m_Idx_Spread_Rate,
                                   p_eff_inst_dt         => nvl(p_eff_inst_dt,
                                                                m_eff_inst_dt) -- Added for Reschedule on Partially Disbursed Cases
                                   );
      END IF;
    --end
    IF m_Retmsg = 'T' AND p_Level_Flag IS NULL THEN
          Pkg_Restructure.Prc_Restructure_Request(p_Org_Code            => p_Org_Code,
                                                p_Loan_Account_No     => p_Loan_Account_No,
                                                p_Trandate            => to_char(p_Business_Date,'dd/mm/yyyy'),


                                                p_Tranche_No          => m_Tranche_No,
                                                p_Trantype            => m_Trantype,
                                                p_Tranhead            => m_Tranhead,
                                                p_Osamount            => m_Osamt,
                                                p_Waive_Amount        => m_Waive_Amount, ------0|0|
                                                p_Due_Amount          => m_Due_Amount, -------------------
                                                p_Cap_Amount          => m_Cap_Amount, -----------------
                                                p_Total_Amount        => m_Total_Amount, --------------
                                                p_Dre_Amount          => 0, -----------------------
                                                p_New_Product         => m_Product_Code,
                                              p_Change_Factor   => CASE
                                                                     WHEN p_Change_Factor IN ('E', 'I') THEN



                                                                      'T'
                                                                     ELSE
                                                                      'E'
                                                                   END, --'E', ---ISSUE FIXED 153085
                                              p_Installment_Amt     => m_Installment_Amt,--m_Emi,
                                                p_Tenor               => TO_NUMBER(m_Tenor),
                                                p_Interest_Rate       => m_Interestrate,
                                                p_New_Asset_Class     => '',
                                                p_Request_Id          => NULL,
                                              p_Reason          => p_Reason || '|' ||
                                                                   TO_CHAR(Nvl(p_Eff_Inst_Dt,
                                                                       m_Eff_Inst_Dt),'DD/MM/yyyy'), -- Added for Reschedule on Partially Disbursed Cases


                                                p_Remark              => NULL,
                                                p_Str_Separator       => '|',
                                                p_Businessdate        => to_char(p_Business_Date,'dd/mm/yyyy'),


                                                p_User_Id             => p_Userid,
                                                p_Return_Msg          => m_Proc_Retmsg, ------OUT VARCHAR2,-------------------------VALIDATIONS
                                                p_Repayment_Frequency => p_Repay_Freq,
                                                p_Repayment_Prin_Freq => NULL,--m_Equated_Prin, --NULL,
                                                p_Variationxml        => m_Xml_Data,
                                                p_Adj_Bpi_Nxt_Inst    => m_Bpi_Recovery_Flag, ----------------------
                                                p_Cycleday            => nvl(p_Cycleday,M_CYCLE_DAY),


                                                p_Interest_Type       => m_Interest_Type,
                                                p_Index_Code          => m_Index_Code,
                                                p_Index_Rate          => m_Index_Rate,
                                                p_Offset_Rate         => m_Max_Offsetrate,
                                                p_Spread_Rate         => m_Idx_Spread_Rate,
                                                p_Purpose             => 'RESCHEDULE',
                                                p_Spread_Code         => m_Spread_Code,
                                              p_Topup_Amount        => NULL,
                                                p_Date_Format=>'dd/MM/yyyy');
        /* IF m_Proc_Retmsg <> 'T' THEN
          RAISE Err_Reschedule_Req;
        END IF;*/
        IF m_Proc_Retmsg =
           'PDC1002|' || Nvl(m_Locking_Period, 0) || '|Year' THEN
          /* m_Retmsg := m_Retmsg ||
                      '###ERROR:Selected Product violating locking Year period of ' ||
          Nvl(m_Locking_Period, 0);*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R39',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' ||
                       Nvl(m_Locking_Period, 0);
        ELSIF m_Proc_Retmsg =
              'PDC1002|' || Nvl(m_Locking_Period, 0) || '|Month' THEN
          /*  m_Retmsg := m_Retmsg ||
                      '###ERROR:Selected Product violating locking Month period of ' ||
          Nvl(m_Locking_Period, 0);*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R40',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' ||
                       Nvl(m_Locking_Period, 0);
        ELSIF m_Proc_Retmsg =
              'PDC1002|' || Nvl(m_Locking_Period, 0) || '|Week' THEN
          /*    m_Retmsg := m_Retmsg ||
                      '###ERROR:Selected Product violating locking Week period of ' ||
          Nvl(m_Locking_Period, 0);*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R41',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' ||
                       Nvl(m_Locking_Period, 0);
        ELSIF m_Total_Amount <= 0 THEN
          ---added by APRANSHU,-- if (p_Total_Amount-p_Dre_Amount)<=0
          /* m_Retmsg := m_Retmsg ||
          '###ERROR: DRE payable amount can not be greater than the sum of capitalize amount';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R42',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        END IF;
      
        CASE
          WHEN m_Proc_Retmsg = 'REST001' THEN
            /* m_Retmsg := m_Retmsg ||
            '###ERROR:Reschedule can be done for live accounts only';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R43',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST003' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Account should be NPA before reschedule';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R44',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST004' THEN
            /* m_Retmsg := m_Retmsg ||
            '###ERROR:Account can not reschedule, as cheque is in transit for this Account';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R45',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST005' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Reschedule can not be done for lease portfolio';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R46',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST021' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Please check the parameters, can not reschedule the request';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R47',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
            /*
            WHEN p_Return_Msg='REST006' THEN
             m_Retmsg := m_Retmsg ||
                          '###ERROR:Reschedule request already exists';
               */
          WHEN m_Proc_Retmsg = 'REST007' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Account can not reschedule, as there is pending request for restructure DRE';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R48',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST011' THEN
            /*m_Retmsg := m_Retmsg || '###ERROR:Error in uploading data';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R49',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST008' THEN
            /*m_Retmsg := m_Retmsg || '###ERROR:Data is inconsistent';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R50',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST009' THEN
            /* m_Retmsg := m_Retmsg ||
            '###ERROR:Instrument Amount should be greater than or equal to the Reschedule Amount';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R51',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST010' THEN
            --m_Retmsg := m_Retmsg || '###ERROR:Customer no. does not exists';
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R52',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST012' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Reschedule is allowed only once for a Account through its life term';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R53',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST013' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Reschedule can not done for partially disbused cases';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R54',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST015' THEN
            /* m_Retmsg := m_Retmsg ||
            '###ERROR:Please Reschedule the body contract first.';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R55',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST002|M' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR: Account can not reschedule, as Account is near to mature';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R56',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST002|RD' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Account can not reschedule, as there is pending request for restructure DRE';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R57',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST002|PP' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Pending request exist for Prepayment can not make a new Reschedule request';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R58',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST002|PF' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Pending request exist for FullPrepayment can not make a new Reschedule request';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R59',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST002|PS' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Account can not reschedule, as there is pending request for settlement';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R60',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST002|PD' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Account can not reschedule, as there is pending request for settlement DRE';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R61',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST002|FF' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Account can not reschedule, as Account is fully prepaid';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R62',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST002|W' THEN
            /* m_Retmsg := m_Retmsg ||
            '###ERROR:Account can not reschedule, as Account is written off';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R63',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST002|S' THEN
            /*m_Retmsg := m_Retmsg ||
            '###ERROR:Account can not reschedule, as Account is settled';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R64',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN m_Proc_Retmsg = 'REST002|R' THEN
            /* m_Retmsg := m_Retmsg ||
            '###ERROR:Account can not reschedule, as Account is repossessed';*/
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R65',
                                                 p_File_Name => p_Filename);
            m_Retmsg  := m_Retmsg || m_Err_Msg;
          WHEN Nvl(m_Proc_Retmsg, 'T') = 'T' THEN
            m_Retmsg := NULL;
        WHEN Nvl(m_Proc_Retmsg, 'T') <> 'T' THEN
          m_Retmsg := m_Proc_Retmsg;  
          ELSE
            --m_Retmsg := m_Retmsg || '###ERROR:Amort Error';
            m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                 p_Tran_Type => m_Module,
                                                 p_Err_Code  => 'R66',
                                                 p_File_Name => p_Filename);
          m_Retmsg  := m_Proc_Retmsg || m_Err_Msg;
        END CASE;
      if m_Retmsg is null then
        Prc_Lms_Bulk_Aayu_Err(p_Err_Msg => m_Proc_Retmsg);
        m_Retmsg := m_Retmsg || m_Proc_Retmsg;
      end if;
      --END IF;
    UPDATE t_Lms_Genbulk_Reschedule t
       SET Sz_Stage2_Err = Sz_Stage2_Err || m_Retmsg
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Loan_Account_No = p_Loan_Account_No
       AND t.Row_Srno = p_Srno;
    END IF;
    /* IF m_Retmsg IS NULL THEN
        Prc_Lms_Bulk_Aayu_Err(p_Err_Msg => m_Proc_Retmsg);
        m_Retmsg := m_Retmsg || m_Proc_Retmsg;
      END IF;
    --END IF;
    UPDATE t_Lms_Genbulk_Reschedule t
       SET Sz_Stage2_Err = Sz_Stage2_Err || m_Retmsg
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Loan_Account_No = p_Loan_Account_No
       AND t.Row_Srno = p_Srno;*/
    --END IF;
    p_Retmsg := 'T';
  EXCEPTION
    WHEN Err_Emi_Tenor_Cal THEN
      p_Retmsg := 'Error in Pkg_Restructure.Prc_Calculate_Emi_Tenor and file name:' ||
                  p_Filename || ':' || Substr(SQLERRM, 1, 2000);
    WHEN Err_Amortz_Param THEN
      p_Retmsg := 'Error in Pkg_Restructure.Prd_Validate_Amortz_Param and file name:' ||
                  p_Filename || ':' || Substr(SQLERRM, 1, 2000);
    WHEN Err_Ext_Resh_Val THEN
      p_Retmsg := 'Error in Pkg_Restructure.Prc_Lms_Bulk_Resch_Extvalue and file name:' ||
                  p_Filename || ':' || m_Reterr;
      /* WHEN Err_Reschedule_Req THEN
          p_Retmsg := 'Error in Pkg_Restructure.Prc_Restructure_Request and file name:' ||
                      p_Filename || ':' || Substr(SQLERRM, 1, 2000);
      */
    WHEN OTHERS THEN
      p_Retmsg := 'Error Occured in Validation for Reschedule and file name:' ||
                  p_Filename || ':' || Substr(SQLERRM, 1, 2000);
  END Prc_Lms_Bulk_Resch_Val;

  PROCEDURE Prc_Lms_Bulk_Aayu_Err(p_Err_Msg IN OUT VARCHAR2) IS
    m_Retmsg VARCHAR2(4000);
  BEGIN
    IF p_Err_Msg = 'ERR_ISNULL' THEN
      m_Retmsg := m_Retmsg || '###ERROR:Field Name is required ';
    ELSIF p_Err_Msg = 'ERR_LENGTH_EXCEED' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Field Name should not be greater than Maxlength ';
    ELSIF p_Err_Msg = 'ERR_NUMBER_FORMAT' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Field Name should be in proper number format ';
    ELSIF p_Err_Msg = 'ERR_AMORT_NOTPOSSIBLE' THEN
      m_Retmsg := m_Retmsg || '###ERROR:Error While Generating Amort ';
    ELSIF p_Err_Msg = 'ERR_INVALID_MONTH' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Step From Month cannot be greater than Step To Month ';
    ELSIF p_Err_Msg = 'ERR_DATE_FORMAT' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Field Name should be in proper date format ';
    ELSIF p_Err_Msg = 'ERR_DATE_INVALID' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Date must be less than or equal to Next Due Date ';
    ELSIF p_Err_Msg = 'ERR_BALLOON_INVALID' THEN
      m_Retmsg := m_Retmsg || '###ERROR:Please specify balloon values ';
    ELSIF p_Err_Msg = 'ERR_SKIP_INVALID' THEN
      m_Retmsg := m_Retmsg || '###ERROR:Please Specify Skip Values ';
    ELSIF p_Err_Msg = 'ERR_STEPUP_INVALID' THEN
      m_Retmsg := m_Retmsg || '###ERROR:Please specify step values ';
    ELSIF p_Err_Msg = 'ERR_VALUE_INVALID' THEN
      m_Retmsg := m_Retmsg || '###ERROR:Is not valid for this amort type ';
    ELSIF p_Err_Msg = 'ERR_STEPUP_MONTH' THEN
      m_Retmsg := m_Retmsg || '###ERROR:Stepping month is invalid ';
    ELSIF p_Err_Msg = 'ERR_SKIP_MONTH' THEN
      m_Retmsg := m_Retmsg || '###ERROR:Skipping month is invalid ';
    ELSIF p_Err_Msg = 'ERR_BALLOON_MONTH' THEN
      m_Retmsg := m_Retmsg || '###ERROR:Balloon month is invalid ';
    ELSIF p_Err_Msg = 'ERR_INVALID_STEPMONTH' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Stepup month cannot be same as Balloon / Stepup / Skipping Month ';
    ELSIF p_Err_Msg = 'ERR_INVALID_SKIPMONTH' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Stepup month cannot be same as Balloon / Stepup / Skipping Month ';
    ELSIF p_Err_Msg = 'ERR_INVALID_BALLOONMONTH' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Balloon month cannot be same as Balloon /Stepup/Skipping Month ';
    ELSIF p_Err_Msg = 'ERR_COMPONENT_INVALID' THEN
      m_Retmsg := m_Retmsg || '###ERROR:Please specify Component values ';
    ELSIF p_Err_Msg = 'ERR_CHARLENGTH_EXCEED' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Field name should not be greater than Maxlength ';
    ELSIF p_Err_Msg = 'ERR_INVALID_ROUNDUNIT' THEN
      m_Retmsg := m_Retmsg || '###ERROR:Invalid Rounding Unit ';
    ELSIF p_Err_Msg = 'ERR_ADJUSTED_EMI' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Adjusted EMI is not possible if EMI is given ';
    ELSIF p_Err_Msg = 'ERR_INT_AMORT_FREQUENCY' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Repayment frequency should be monthly when going for internal Amort ';
    ELSIF p_Err_Msg = 'ERR_INPUT_PARAMETERS' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Principal,EMI,Tenor,Interest Rate can not be provided together ';
    ELSIF p_Err_Msg = 'ERR_OSP_GREATERTHAN_EMI' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Principal is greater than EMI in Last installment ';
    ELSIF p_Err_Msg = 'ERR_ADVAMT' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR: If the outstanding principal is not sufficient to generate the EMI with variation ';
    ELSIF p_Err_Msg = 'ERR_NEGATIVE_AMORT' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR: Installment Amount Should be greater than interest amount ';
    ELSIF p_Err_Msg = 'ERR_NEGATIVE_AMORT' THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR: Installment Amount Should be greater than interest amount ';
    ELSE
      m_Retmsg := NULL;
    END IF;
    p_Err_Msg := m_Retmsg;
  END Prc_Lms_Bulk_Aayu_Err;

  PROCEDURE Prc_Lms_Bulk_Resch_Extvalue(p_Org_Code        IN VARCHAR2,
                                        p_Loan_Account_No IN VARCHAR2,
                                        p_Trantype        OUT VARCHAR2,
                                        p_Tranhead        OUT VARCHAR2,
                                        p_Osamt           OUT VARCHAR2,
                                        p_Taxamt          OUT VARCHAR2,
                                        p_Tranche_No      OUT VARCHAR2,
                                        p_Waive_Amt       OUT VARCHAR2,
                                        p_Cap_Amt         OUT VARCHAR2,
                                        p_Due_Amt         OUT VARCHAR2,
                                        p_Total_Amt       OUT NUMBER,
                                        p_Retmsg          OUT VARCHAR2) IS
    m_Cnt            NUMBER := 0;
    m_Osamt1         NUMBER := 0;
    m_Cap            VARCHAR2(100);
    m_Cap1           NUMBER := 0;
    m_Capl1          VARCHAR2(100);
    m_Capl2          NUMBER := 0;
    m_Waiver_Amount1 NUMBER := 0;
    --m_Total_Amt      NUMBER := 0;
    m_Due1 VARCHAR2(100);
    m_Due2 VARCHAR2(100);
    --m_Due_Amt        VARCHAR2(100);
  BEGIN
    SELECT Listagg(k.Sz_Trantype, '|') Within GROUP(ORDER BY k.t) || '|' Sz_Trantype,
           Listagg(k.Tranhead, '|') Within GROUP(ORDER BY k.t) || '|' Tranhead,
           Listagg(k.Osamt, '|') Within GROUP(ORDER BY k.t) || '|' Osamt,
           Listagg(k.Taxamt, '|') Within GROUP(ORDER BY k.t) || '|' Taxamt,
           Listagg(k.i_Tranche_No, '|') Within GROUP(ORDER BY k.t) || '|' i_Tranche_No,
           Listagg(k.Waiveamt, '|') Within GROUP(ORDER BY k.t) || '|' Waiveamt
      INTO p_Trantype,
           p_Tranhead,
           p_Osamt,
           p_Taxamt,
           p_Tranche_No,
           p_Waive_Amt
      FROM (SELECT Sz_Org_Code,
                   Sz_Loan_Account_No,
                   i_Tranche_No,
                   Sz_Trantype,
                   Tranhead,
                   CASE Sz_Trantype
                     WHEN 'INSTALLMENT' THEN
                      1
                     WHEN 'LOAN_AMOUNT' THEN
                      2
                     WHEN 'FEE' THEN
                      3
                     WHEN 'SUB_PRODUCT' THEN
                      4
                   END t,
                   Tranheadds,
                   SUM(Osamt) Osamt,
                   Taxamt Taxamt,
                   '0' Waiveamt
              FROM (SELECT d.Sz_Org_Code,
                           d.Sz_Loan_Account_No,
                           Decode(d.Sz_Trantype, 'FEE', '1', d.i_Tranche_No) i_Tranche_No,
                           d.Sz_Trantype,
                           d.Tranhead,
                           (SELECT t.Sz_Head_Desc
                              FROM v_Lms_Restruct_Tran_Head t
                             WHERE t.Sz_Org_Code = d.Sz_Org_Code
                               AND t.Szcode = d.Tranhead) Tranheadds,
                           Nvl(SUM(d.Osamt), 0) Osamt,
                           Nvl(SUM(d.Taxamt), 0) Taxamt
                      FROM v_Lms_Head_Wise_Due d
                     WHERE d.Osamt > 0
                       AND d.Sz_Org_Code = p_Org_Code
                       AND d.Sz_Loan_Account_No = p_Loan_Account_No
                     GROUP BY d.Sz_Org_Code,
                              d.Sz_Loan_Account_No,
                              d.i_Tranche_No,
                              d.Sz_Trantype,
                              d.Tranhead,
                              d.Tranheadds)
             WHERE Sz_Org_Code = p_Org_Code
               AND Sz_Loan_Account_No = p_Loan_Account_No
               AND Sz_Trantype IN ('LOAN_AMOUNT', 'BPI')
             GROUP BY Sz_Org_Code,
                      Sz_Loan_Account_No,
                      i_Tranche_No,
                      Sz_Trantype,
                      Tranhead,
                      Tranheadds,
                      Taxamt
             ORDER BY t,
                      CASE Tranhead
                        WHEN 'PRN_AMT' THEN
                         1
                        WHEN 'INT_AMT' THEN
                         2
                        ELSE
                         3
                      END) k;
    m_Cnt := Regexp_Count(p_Tranhead, '[|]');
  
    FOR k IN 1 .. m_Cnt LOOP
      IF Regexp_Substr(p_Trantype, '[^|]+', 1, k) = 'LOAN_AMOUNT' THEN
        m_Osamt1         := Regexp_Substr(p_Osamt, '[^|]+', 1, k);
        m_Waiver_Amount1 := Regexp_Substr(p_Waive_Amt, '[^|]+', 1, k);
        m_Capl1          := m_Capl1 || (m_Osamt1 - m_Waiver_Amount1) || '|';
        m_Capl2          := m_Capl2 + (m_Osamt1 - m_Waiver_Amount1);
        m_Due1           := m_Due1 ||
                            (m_Osamt1 - m_Waiver_Amount1 - m_Capl2) || '|';
        -- m_due2:= M_osamt1-M_waiver_amount1-m_capl2;
      ELSE
        m_Osamt1         := Regexp_Substr(p_Osamt, '[^|]+', 1, k);
        m_Waiver_Amount1 := Regexp_Substr(p_Waive_Amt, '[^|]+', 1, k);
        m_Cap            := m_Cap || '0|';
        m_Cap1           := m_Cap1 + 0;
/*        m_Due2           := m_Due2 ||
                            (m_Osamt1 - m_Waiver_Amount1 - m_Cap1) || '|';*/
        m_Due2           := m_Due2 || '0|';
        --m_due4:= M_osamt1-M_waiver_amount1-M_CAP1;
        -- Dbms_Output.Put_Line('due2=' || m_Due2);
      END IF;
      --  Dbms_Output.Put_Line('OS1=' || m_Osamt1);
    
    END LOOP;
    /*M_CAP_AMT:=m_Capl1 || m_Cap
    m_Total_Amt := m_Capl2 + m_Cap1;
    m_Due_Amt   := m_Due1 || m_Due2;*/
  
    --Dbms_Output.Put_Line('Cap=' || m_Capl1 || m_Cap);
    -- Dbms_Output.Put_Line('total=' || m_Total_Amt);
    --Dbms_Output.Put_Line('due amt=' || m_Due_Amt);
    p_Cap_Amt   := m_Capl1 || m_Cap;
    p_Total_Amt := m_Capl2 + m_Cap1;
    p_Due_Amt   := m_Due1 || m_Due2;
    p_Retmsg    := 'T';
  EXCEPTION
    WHEN OTHERS THEN
      p_Retmsg := Substr(SQLERRM, 1, 2000);
  END Prc_Lms_Bulk_Resch_Extvalue;

  PROCEDURE Prc_Lms_Bulk_Job(p_Org_Code  IN VARCHAR2,
                             p_Flag      IN VARCHAR2,
                             p_Tran_Type IN VARCHAR2) AS
  
    m_Jobno         NUMBER;
    m_Business_Date VARCHAR2(1000) := Trunc(Fun_Getbusinessdate(p_Org_Code));
    Mstr            VARCHAR2(4000);
    m               DATE;
  BEGIN
  
    /*  Sys.Dbms_Job.Submit(Job  => m_Jobno,
                         What => 'BEGIN
     Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Common(p_Org_Code      => '''||p_Org_Code||''',
                                                p_Business_Date => NULL,
                                                p_Status        => '''||p_Flag||''',
                                                p_Tran_Type     => '''||p_Tran_Type || '''); END;'
                                                );
    */
  
    Sys.Dbms_Job.Submit(m_Jobno,
                        'BEGIN PKG_LMS_BULK_OPERATION.PRC_LMS_BULK_COMMON(''' ||
                        p_Org_Code || ''',NULL,''' || p_Flag || ''',''' ||
                        p_Tran_Type || '''); END;');
  
    /*  Mstr := 'BEGIN PKG_LMS_BULK_OPERATION.PRC_LMS_BULK_COMMON(''' ||
               p_Org_Code || ''',NULL,''' || p_Flag || ''',''' || p_Tran_Type ||
               '''); END;';
    */
    --RETURN;
    --EXECUTE IMMEDIATE Mstr;
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      Dbms_Output.Put_Line(SQLERRM);
  END Prc_Lms_Bulk_Job;

  PROCEDURE Prc_Lms_Bulk_Reject(p_Org_Code      IN VARCHAR2,
                                p_Business_Date IN DATE) IS
  BEGIN
    UPDATE t_Lms_Bulk_Tran_Details k
       SET k.c_Checker_Status = 'R', k.c_Batch_Status = 'C'
     WHERE k.Sz_Org_Code = p_Org_Code
       AND k.c_Checker_Status IS NULL;
  
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END Prc_Lms_Bulk_Reject;
  --------------dre process started
  PROCEDURE Prc_Lms_Bulk_Dre(p_Org_Code      IN VARCHAR2,
                             p_File_Name     IN VARCHAR2,
                             p_Business_Date IN DATE,
                             p_Outstr        OUT VARCHAR2) IS
    TYPE Type_Dre IS TABLE OF t_Lms_Genbulk_Dre%ROWTYPE;
    Rec_Dre  Type_Dre := Type_Dre();
    m_Retstr VARCHAR2(4000);
    Err_Dre_Setup EXCEPTION;
    Err_Dre_Val EXCEPTION;
    Err_Level2_Insert EXCEPTION;
    TYPE Type_Col IS TABLE OF VARCHAR2(4000);
    m_Rec_Columns Type_Col := Type_Col();
    m_Colname     VARCHAR2(4000);
    m_Colname1    VARCHAR2(4000);
    m_Err2_Cnt    NUMBER := 0;
  BEGIN
    Prc_Lms_Bulk_Setup_Val(p_Org_Code  => p_Org_Code,
                           p_Filename  => p_File_Name,
                           p_Tran_Type => 'DRE',
                           p_Retmsg    => m_Retstr);
    IF m_Retstr <> 'T' THEN
      RAISE Err_Dre_Setup;
    END IF;
    SELECT * BULK COLLECT

      INTO Rec_Dre
      FROM t_Lms_Genbulk_Dre t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Filename = p_File_Name
       AND t.Sz_Errmsg IS NULL
       AND t.Sz_Stage2_Err IS NULL;
    IF Rec_Dre.Count > 0 THEN
      FOR i IN Rec_Dre.First .. Rec_Dre.Last LOOP
        Prc_Lms_Bulk_Dre_Val(p_Org_Code          => p_Org_Code,
                             p_Srno              => Rec_Dre(i).Row_Srno,
                             p_Loan_Account_No   => Rec_Dre(i)
                                                    .Sz_Loan_Account_No,
                             p_Dre_Amount        => Rec_Dre(i).f_Dre_Amount,
                             p_Instrument_Type   => Upper(Rec_Dre(i)
                                                          .Sz_Instrument_Type),
                             p_Instrument_Loc    => Upper(Rec_Dre(i)
                                                          .Sz_Instrument_Loc),
                             p_Instrument_No     => Rec_Dre(i)
                                                    .i_Instrument_No,
                             p_Ifsc_Code         => Upper(Rec_Dre(i)
                                                          .Sz_Ifsc_Code),
                             p_Bank_Code         => Upper(Rec_Dre(i)
                                                          .Sz_Bank_Code),
                             p_Bank_Branch_Code  => Upper(Rec_Dre(i)
                                                          .Sz_Bank_Branch_Code),
                             p_Account_Type      => Upper(Rec_Dre(i)
                                                          .Sz_Account_Type),
                             p_Bank_Accountno    => Upper(Rec_Dre(i)
                                                          .Sz_Bank_Accountno),
                             p_Deposit_Bank_Code => Upper(Rec_Dre(i)
                                                          .Sz_Deposit_Bank_Code),
                             p_Instrument_Date   => Rec_Dre(i).Dt_Instrument,
                             p_Utr_Number        => Upper(Rec_Dre(i)
                                                          .Sz_Utr_Number),
                             p_Value_Date        => Rec_Dre(i).Dt_Value_Date,
                             p_File_Name         => p_File_Name,
                             p_Business_Date     => p_Business_Date,
                             p_Userid            => Rec_Dre(i).Sz_Userid,
                             p_card_type         => Rec_Dre(i).SZ_FIELD2, -- issue fixed : 149575(removed upper function)
                             p_CARD_HOLDER_NM    => Rec_Dre(i)
                                                    .SZ_CARD_HOLDER_NM,
                             P_DC_ISSUING_BANK   => Rec_Dre(i)
                                                    .SZ_DC_ISSUING_BANK,
                             P_CARD_EXP_DATE     => Rec_Dre(i).SZ_FIELD3,
                             P_MOB_NO            => Rec_Dre(i).SZ_FIELD4,
                             P_CARD_SUBTYPE      => Rec_Dre(i).SZ_CARD_TYPE,
                             P_UPI_VPA           => Rec_Dre(i).SZ_UPI_VPA,
                             P_DT_RECEIPT        => Rec_Dre(i).DT_RECEIPT,
                             P_DEPOSIT_REF_NO    => Rec_Dre(i)
                                                    .SZ_DEPOSIT_REF_NO,
                             P_PROC_LOC          => Rec_Dre(i).SZ_PROC_LOC, -- IBT Issue Fix : 156385                
                             p_Retmsg            => m_Retstr);
        IF m_Retstr <> 'T' THEN
          RAISE Err_Dre_Val;
        END IF;
      END LOOP;
    END IF;
    ---LEVEL 2 ERROR LOG
    SELECT COUNT(1)
      INTO m_Err2_Cnt
      FROM t_Lms_Genbulk_Dre r
     WHERE r.Sz_Org_Code = p_Org_Code
       AND r.Sz_Filename = p_File_Name
       AND r.Sz_Stage2_Err IS NOT NULL;
    IF m_Err2_Cnt > 0 THEN
      SELECT TRIM(Ut.Column_Name) Column_Name BULK COLLECT
        INTO m_Rec_Columns
        FROM User_Tab_Columns Ut
       WHERE Ut.Table_Name = 'T_LMS_GENBULK_DRE'
         AND Ut.Column_Name NOT IN ('SZ_STAGE2_ERR',
                                    'SZ_ERRMSG',
                                    'SZ_FILENAME',
                                    'DT_LASTUPDATED',
                                    'SZ_USERID',
                                    'C_VDT_FLAG',
                                    'SZ_ORG_CODE')
       ORDER BY Ut.Column_Id;
      FOR i IN m_Rec_Columns.First .. m_Rec_Columns.Last LOOP
        m_Colname  := m_Rec_Columns(i);
        m_Colname1 := m_Colname1 || '$' || m_Colname;
        m_Colname1 := TRIM(Leading '$' FROM m_Colname1);
        m_Colname1 := REPLACE(m_Colname1, '$', '||'',''||');
      END LOOP;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Level_Err_Insert(p_Org_Code   => p_Org_Code,
                                                           p_Columns    => m_Colname1,
                                                           p_Tran_Type  => 'DRE',
                                                           p_Tran_Table => 'T_LMS_GENBULK_DRE',
                                                           p_File_Name  => p_File_Name,
                                                           p_Level      => 'LEVEL-2',
                                                           p_Retmsg     => m_Retstr);
      IF m_Retstr <> 'T' THEN
        RAISE Err_Level2_Insert;
      END IF;
    END IF;
    --END LEVEL 2 ERROR LOG
    p_Outstr := 'T';
  EXCEPTION
    WHEN Err_Dre_Setup THEN
      p_Outstr := m_Retstr;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_DRE_Setup_Val',
                                                    p_Errmsg   => m_Retstr);
    WHEN Err_Dre_Val THEN
      p_Outstr := m_Retstr;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_DRE_Val',
                                                    p_Errmsg   => m_Retstr);
    WHEN Err_Level2_Insert THEN
      p_Outstr := '-101';
      m_Retstr := 'Error occured for LEVEL-2 DRE::' || m_Retstr;
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Level_Err_Insert',
                                                    p_Errmsg   => m_Retstr);
    WHEN OTHERS THEN
      p_Outstr := 'Error Occured in DRE process for file name:' ||
                  p_File_Name || ':' || Substr(SQLERRM, 1, 2000);
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_DRE_Process',
                                                    p_Errmsg   => p_Outstr);
  END Prc_Lms_Bulk_Dre;
  ---3
  PROCEDURE Prc_Lms_Bulk_Dre_Val(p_Org_Code          IN VARCHAR2,
                                 p_Srno              NUMBER,
                                 p_Loan_Account_No   IN VARCHAR2,
                                 p_Dre_Amount        IN VARCHAR2, -- issue fix 149646
                                 p_Instrument_Type   IN VARCHAR2,
                                 p_Instrument_Loc    IN VARCHAR2 DEFAULT NULL,
                                 p_Instrument_No     IN VARCHAR2 DEFAULT NULL,
                                 p_Ifsc_Code         IN VARCHAR2 DEFAULT NULL,
                                 p_Bank_Code         IN VARCHAR2 DEFAULT NULL,
                                 p_Bank_Branch_Code  IN VARCHAR2 DEFAULT NULL,
                                 p_Account_Type      IN VARCHAR2 DEFAULT NULL,
                                 p_Bank_Accountno    IN VARCHAR2 DEFAULT NULL,
                                 p_Deposit_Bank_Code IN VARCHAR2 DEFAULT NULL,
                                 p_Instrument_Date   IN DATE DEFAULT NULL,
                                 p_Utr_Number        IN VARCHAR2 DEFAULT NULL,
                                 p_Value_Date        IN DATE DEFAULT NULL,
                                 p_File_Name         IN VARCHAR2,
                                 p_Business_Date     IN DATE,
                                 p_Userid            IN VARCHAR2,
                                 P_LEVEL_FLAG        IN VARCHAR2 DEFAULT NULL,
                                 p_card_type         IN VARCHAR2 DEFAULT NULL,
                                 p_CARD_HOLDER_NM    IN VARCHAR2 DEFAULT NULL,
                                 P_DC_ISSUING_BANK   IN VARCHAR2 DEFAULT NULL,
                                 P_CARD_EXP_DATE     IN VARCHAR2 DEFAULT NULL,
                                 P_MOB_NO            IN VARCHAR2 DEFAULT NULL,
                                 P_CARD_SUBTYPE      IN VARCHAR2 DEFAULT NULL,
                                 P_UPI_VPA           IN VARCHAR2 DEFAULT NULL,
                                 P_DT_RECEIPT        IN DATE,
                                 P_DEPOSIT_REF_NO    IN VARCHAR2 DEFAULT NULL,
                                 P_PROC_LOC          IN VARCHAR2 DEFAULT NULL, -- Added for IBT Enh.
                                 p_Retmsg            OUT VARCHAR2) IS
    m_Retmsg            VARCHAR2(4000);
    m_Err_Msg           VARCHAR2(4000);
    m_Module            VARCHAR2(10);
    m_Preturn           VARCHAR2(4000);
    m_Datediff          NUMBER;
    m_Rangedt           DATE;
    m_Disbflag          CHAR(1) := 'Y';
    m_Account_Status    t_Lms_Loan_Account.c_Account_Status%TYPE;
    m_Additional_Status t_Lms_Loan_Account.c_Additional_Status%TYPE;
    m_Cnt               NUMBER := 0;
    m_Asstcnt           NUMBER := 0;
    m_Customer_No       t_Lms_Loan_Account.Sz_Customer_No%TYPE;
    m_Tran_Head         VARCHAR2(4000);
    m_Apor_Amt          VARCHAR2(4000); --NUMBER := 0;
    m_Tran_Id           VARCHAR2(1000);
    m_Receipt_No        NUMBER := 0;
    m_Inst_Coll         VARCHAR2(1000);
    m_Inst_Pay_Op       VARCHAR2(1000);
    m_Tds_Amt           VARCHAR2(1000);
    m_Man_Apportion     VARCHAR2(1000);
    m_Return_Msg        VARCHAR2(4000);
    m_Loan_Account_No   t_Lms_Loan_Account.Sz_Loan_Account_No%TYPE;
    m_Micr_Code         v_Mst_Bank_Branch.Szmicrcode%TYPE;
    m_Dre_Amount        VARCHAR2(4000);
    m_Reterr            VARCHAR2(4000);
    Err_Ext_Dre_Val EXCEPTION;
    --m_Value_Date      DATE;
    m_Vdt_Flag        CHAR(1) := 'N';
    m_Bank_Code       Cmn_Vew_Bankbranch_Master.Sz_Bank_Code%TYPE;
    m_Bankbranch_Code Cmn_Vew_Bankbranch_Master.Sz_Bankbranch_Code%TYPE;
    m_Instrument_Date DATE := Trunc(p_Instrument_Date);
    m_Utr_Cnt         NUMBER := 0;
    m_Utr_Cnt1        NUMBER := 0;
    m_lan_count       number := 0;
    m_Lan             VARCHAR2(4000);
    m_Apor_Amt1       VARCHAR2(4000);
    m_Allocated_Lan   VARCHAR2(4000);
  BEGIN
    m_Retmsg := NULL;
    
    Prc_Dre_Screen_Validations(p_Org_Code          => p_Org_Code,
                                 p_Srno             => p_Srno,
                                 p_Loan_Account_No   => p_Loan_Account_No,
                                 p_Dre_Amount        => p_Dre_Amount,
                                 p_Instrument_Type   => p_Instrument_Type,
                                 p_Instrument_Loc    => p_Instrument_Loc,
                                 p_Instrument_No     => p_Instrument_No,
                                 p_Ifsc_Code         => p_Ifsc_Code,
                                 p_Bank_Code         => p_Bank_Code,
                                 p_Bank_Branch_Code  => p_Bank_Branch_Code,
                                 p_Account_Type      => p_Account_Type,
                                 p_Bank_Accountno    => p_Bank_Accountno,
                                 p_Deposit_Bank_Code => p_Deposit_Bank_Code,
                                 p_Instrument_Date   => p_Instrument_Date,
                                 p_Utr_Number        => p_Utr_Number,
                                 p_Value_Date        => p_Value_Date,
                                 p_File_Name         => p_File_Name,
                                 p_Business_Date     => p_Business_Date,
                                 p_Userid            => p_Userid,
                                 P_LEVEL_FLAG        => P_LEVEL_FLAG,
                               p_card_type         => p_card_type,
                               p_CARD_HOLDER_NM    => p_CARD_HOLDER_NM,
                               P_DC_ISSUING_BANK   => P_DC_ISSUING_BANK,
                               p_Card_Exp_Date     => p_Card_Exp_Date, /*To_Char(To_Date(p_Card_Exp_Date,
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      'MON-RR'),
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              'MM/YYYY'),*/ -- Issue Fix : 150310
                               P_MOB_NO            => P_MOB_NO,
                               P_CARD_SUBTYPE      => P_CARD_SUBTYPE,
                               P_DEPOSIT_REF_NO    => P_DEPOSIT_REF_NO, -- Issue fix : 149372
                               P_DT_RECEIPT        => P_DT_RECEIPT, -- Issue Fix : 149367
                               P_UPI_VPA           => P_UPI_VPA, --issue fix : 149646 on 9th Mar 2017                                                                                                                                                                                                                                                         
							   P_PROC_LOC          => P_PROC_LOC, -- Added for IBT Enh.
                                 p_Retmsg            => m_Retmsg);
    
    
    -------ONLY SECOND LEVEL VALIDAIONS---------
    IF p_Level_Flag IS NULL AND m_Retmsg='T' THEN
      m_Retmsg:=null;
      IF m_Instrument_Date IS NULL THEN
        m_Instrument_Date:=p_Business_Date;
      END IF;
        m_Module          := 'DRE';
        m_Loan_Account_No := p_Loan_Account_No || '|';
      m_Apor_Amt        := '0|'; --chcek
        m_Dre_Amount      := p_Dre_Amount || '|';
        m_Tds_Amt         := '0|';
        BEGIN
          SELECT b.Szname
            INTO m_Inst_Coll
            FROM Base_Org_Mst_Businessunit b
           WHERE b.Szorg_Id = Fun_Get_Org_Id(p_Org_Code)
             AND b.Szparent_Business_Unit_Id IS NULL;
        EXCEPTION
          WHEN OTHERS THEN
            m_Inst_Coll := 'BS';
        END;
        SELECT T.SZ_CUSTOMER_NO
          INTO m_Customer_No
          FROM T_LMS_LOAN_ACCOUNT T
         WHERE T.SZ_ORG_CODE = p_Org_Code
           AND T.SZ_LOAN_ACCOUNT_NO = p_Loan_Account_No;
        BEGIN
          SELECT Nvl(Tt.c_Inst_Pay_Opt, 'G') || '|'
            INTO m_Inst_Pay_Op
            FROM t_Lms_Loan_References Lr, t_Lms_Loan_Account Tt
           WHERE Tt.Sz_Org_Code = Lr.Sz_Org_Code
             AND Tt.Sz_Loan_Account_No = Lr.Sz_Loan_Account_No
             AND (Lr.Sz_Customer_No = m_Customer_No OR
                 Lr.Sz_Loan_Account_No = p_Loan_Account_No)
             AND Lr.Sz_Org_Code = p_Org_Code
             AND Lr.c_Typeofapplicant = 'B';
        EXCEPTION
          WHEN OTHERS THEN
            m_Inst_Pay_Op := 'G|';
        END;
        IF p_Instrument_Type <> 'CA' AND p_Ifsc_Code IS NOT NULL THEN
          BEGIN
            SELECT m.Sz_Bank_Code, m.Sz_Bankbranch_Code, m.Sz_Micr_Code
              INTO m_Bank_Code, m_Bankbranch_Code, m_Micr_Code
              FROM Cmn_Vew_Bankbranch_Master m
             WHERE m.Sz_Org_Code = p_Org_Code
               AND m.Sz_Ifsc_Code = p_Ifsc_Code;
          EXCEPTION
            WHEN OTHERS THEN
              m_Bank_Code       := NULL;
              m_Bankbranch_Code := NULL;
              m_Micr_Code       := NULL;
          END;
        END IF;
        /* IF p_Ifsc_Code IS NULL THEN
            m_Bank_Code       := p_Bank_Code;
            m_Bankbranch_Code := p_Bank_Branch_Code;
            IF p_Instrument_Type IN ('CH', 'PO', 'DD') THEN
              BEGIN
                SELECT Sz_Micr_Code
                  INTO m_Micr_Code
                  FROM Cmn_Vew_Bankbranch_Master v
                 WHERE v.Sz_Org_Code = p_Org_Code
                   AND v.Sz_Bank_Code = p_Bank_Code
                   AND v.Sz_Bankbranch_Code = p_Bank_Branch_Code
                   AND Rownum <= 1;
              EXCEPTION
                WHEN OTHERS THEN
                  m_Micr_Code := NULL;
              END;
            END IF;
            m_Micr_Code := NULL;
          END IF;
        */
        Prc_Lms_Bulk_Dre_Extvalue(p_Org_Code        => p_Org_Code,
                                  p_Loan_Account_No => p_Loan_Account_No,
                                  p_Out_Tranhead    => m_Tran_Head,
                                  p_Retmsg          => m_Reterr);
      
        IF m_Reterr <> 'T' THEN
          m_Tran_Head := '|';
          --RAISE Err_Ext_Dre_Val;
        END IF;
      ----ISSUE FIXED 154170
      FOR i IN 1 .. Regexp_Count(m_Tran_Head, '[|]') LOOP
        m_Lan       := m_Lan || '|';
        m_Apor_Amt1 := m_Apor_Amt1 || '|';
      END LOOP;
      m_Allocated_Lan := REPLACE(m_Lan, '|', m_Loan_Account_No);
      m_Apor_Amt      := REPLACE(m_Apor_Amt1, '|', m_Apor_Amt);
      ----END
        Prc_Lms_Manual_Pay_Data(p_Org_Code           => p_Org_Code, --001
                                p_Sz_Loan_Account_No => m_Loan_Account_No, --AL_01_91005|
                                p_Customer_No        => m_Customer_No, --91005   (Internally)
                                p_Value_Date         => p_Value_Date, --09/09/2016  (VALUE DATE)
                                p_Tran_Type          => m_Module, --DRE
                              p_Allocated_Lan      => m_Allocated_Lan, --m_Loan_Account_No, --AL_01_91005|----issue fixed 154170
                                p_Tran_Head          => m_Tran_Head, --STATEMENT| (Internally)
                                p_Instrument_Type    => p_Instrument_Type, --CA#CH
                                p_Apor_Amt           => m_Apor_Amt, --|  (INTERNALLY PIPE SEPERATED)
                                p_Tran_Id            => m_Tran_Id, ---IN OUT (NULL)
                                p_Receipt_No         => m_Receipt_No, ---IN OUT (NULL)
                                p_Request_Id         => NULL,
                                p_Remark             => NULL,
                                p_User_Id            => p_Userid, --SYSADMIN
                                p_Instrument_Date    => m_Instrument_Date, --09/09/2016
                                p_Payment_Purpose    => 'NORMAL_PAYMENT',
                                p_Account_No         => p_Bank_Accountno, ---8798777797897
                                p_Account_Type       => NULL,
                                p_Instrument_No      => p_Instrument_No, ---979879
                                p_Bank_Code          => m_Bank_Code, --HDFC
                                p_Bank_Branch_Code   => m_Bankbranch_Code, --HDFCEAST
                                p_Micr_Code          => m_Micr_Code, --7888 (INTERNALLY)
                                p_Clearing_Location  => p_Instrument_Loc, --LO
                                p_Inst_Coll_Ser_Loc  => m_Inst_Coll, --BS (INTERNALLY)-----check
                                p_Famount            => p_Dre_Amount,
                                p_Str_Separator      => '|', --|
                                p_Loan_Acc_Alloc     => m_Loan_Account_No, --AL_01_91005|
                                p_Famount_Alloc      => m_Dre_Amount, --3000|
                                p_Inst_Pay_Op_Alloc  => m_Inst_Pay_Op, ---G| (internally) -----check
                                p_Tds_Amt_Alloc      => m_Tds_Amt, --0|
                                p_Ass_Year_Alloc     => '|', --|
                                p_Businessdate       => p_Business_Date, --09/09/2016
                                p_Man_Apportion      => m_Man_Apportion, --NULL
                                p_Deposit_Bank       => p_Deposit_Bank_Code, --DEPSITBNK1  /*added for Instrument processing - De-Centralized Banking*/
                                p_Utr_Number         => p_Utr_Number, --LMS5.7 ENH.
                              p_Proc_Loc           => P_PROC_LOC, -- IBT Issue Fix : 156385 
                                p_Return_Msg         => m_Preturn);
        IF m_Preturn <> 'T' THEN
          if m_Preturn = 'DUP_INSTRUMENT' THEN
            m_Preturn := 'Duplicate Instrument Found';
          END IF;
          m_Retmsg := m_Retmsg || '###ERROR:SAVE FAILED:' || m_Preturn;
        END IF;
      UPDATE t_Lms_Genbulk_Dre t
         SET Sz_Stage2_Err = Sz_Stage2_Err || m_Retmsg
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Sz_Filename = p_File_Name
         AND t.Row_Srno = p_Srno;
    END IF;
    p_Retmsg := 'T';
  EXCEPTION
    WHEN Err_Ext_Dre_Val THEN
      p_Retmsg := 'Error in Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_DRE_Extvalue and file name:' ||
                  p_File_Name || ':' || m_Reterr;
    WHEN OTHERS THEN
      p_Retmsg := 'Error Occured for DRE and file name:' || p_File_Name || ':' ||
                  Substr(SQLERRM, 1, 2000);
  END Prc_Lms_Bulk_Dre_Val;
  PROCEDURE Prc_Lms_Bulk_Dre_Extvalue(p_Org_Code        IN VARCHAR2,
                                      p_Loan_Account_No IN VARCHAR2,
                                      p_Out_Tranhead    OUT VARCHAR2,
                                      p_Retmsg          OUT VARCHAR2) IS
  BEGIN
    SELECT Listagg(k.Tranhead, '|') Within GROUP(ORDER BY k.Lan) || '|' Tranhead
      INTO p_Out_Tranhead
      FROM (SELECT T1.Sz_Org_Code,
                   T1.Lan Lan,
                   SUM(T1.Accountdue) Accountdue,
                   SUM(T1.Apportioned_Amt) Apportioned_Amt,
                   Nvl(SUM(T1.Taxamt), 0) Taxamt,
                   T1.Tranhead Tranhead,
                   T1.Head_Desc Head_Desc,
                   SUM(T1.Accountdue) + Nvl(SUM(T1.Taxamt), 0) Total_Amt,
                   T1.Sz_Trantype Sz_Trantype,
                   SUM(T1.Chg_Booked_Amt) Chgamt,
                   SUM(T1.Tax_Booked_Amt) Chgtaxamt
              FROM (SELECT Ss.Sz_Org_Code,
                           Ss.Sz_Loan_Account_No Lan,
                           Ss.i_Reference_No,
                           SUM(Ss.f_Due_Amt) Accountdue,
                           SUM(Ss.f_Apportioned_Amt) Apportioned_Amt,
                           Ss.Sz_Tranhead Tranhead,
                           Ss.Sz_Trantype,
                           Ss.Head_Desc,
                           SUM(Ss.f_Tax_Amt) Taxamt,
                           (SELECT SUM(t.f_Amount) Charge_Amt
                              FROM t_Lms_Chg_Booking_Dtls t
                             WHERE t.Sz_Org_Code = Ss.Sz_Org_Code
                               AND t.Sz_Loan_Account_No =
                                   Ss.Sz_Loan_Account_No
                               AND t.i_Chgbooktran_Id = Ss.i_Reference_No
                             GROUP BY t.Sz_Org_Code,
                                      t.Sz_Loan_Account_No,
                                      t.i_Chgbooktran_Id,
                                      t.Sz_Tranhead) Chg_Booked_Amt,
                           (SELECT SUM(Ta.f_Tax_Amt) Tax_Amt
                              FROM t_Lms_Tax_Chgbooking Ta
                             WHERE Ta.Sz_Org_Code = Ss.Sz_Org_Code
                               AND Ta.Sz_Loan_Account_No =
                                   Ss.Sz_Loan_Account_No
                               AND Ta.i_Chgbooktran_Id = Ss.i_Reference_No
                             GROUP BY Ta.Sz_Org_Code,
                                      Ta.Sz_Loan_Account_No,
                                      Ta.i_Chgbooktran_Id) Tax_Booked_Amt
                      FROM (SELECT Dd.Sz_Org_Code,
                                   Dd.Sz_Loan_Account_No,
                                   Dd.i_Reference_No,
                                   Dd.f_Due_Amt f_Due_Amt,
                                   Dd.Sz_Tranhead,
                                   Dd.Sz_Trantype,
                                   Dd.f_Apportioned_Amt,
                                   (SELECT Nnn.Szdesc
                                      FROM v_Lms_Transction_Head Nnn
                                     WHERE Nnn.Sz_Org_Code = Dd.Sz_Org_Code
                                       AND Dd.Sz_Tranhead =
                                           (SELECT Decode(Nn.Szcode,
                                                          'DEBIT_NOTE',
                                                          'DEBITNOTE_AMT',
                                                          Nn.Szcode)
                                              FROM v_Lms_Transction_Head Nn
                                             WHERE Nn.Sz_Org_Code =
                                                   Nnn.Sz_Org_Code
                                               AND Nn.Szcode = Nnn.Szcode)) Head_Desc,
                                   (SELECT SUM(Td.f_Tax_Amt)
                                      FROM t_Lms_Taxdue_Dtls Td
                                     WHERE Dd.Sz_Org_Code = Td.Sz_Org_Code
                                       AND Dd.Sz_Loan_Account_No =
                                           Td.Sz_Loan_Account_No
                                       AND Dd.i_Srno = Td.i_Srno) f_Tax_Amt
                              FROM t_Lms_Due_Dtls Dd
                             WHERE Dd.Sz_Org_Code = p_Org_Code
                               AND Dd.Sz_Loan_Account_No IN
                                   (SELECT T1.Sz_Loan_Account_No
                                      FROM t_Lms_Loan_References T1
                                     WHERE (T1.Sz_Customer_No =
                                           p_Loan_Account_No OR
                                           T1.Sz_Loan_Account_No =
                                           p_Loan_Account_No)
                                       AND T1.Sz_Org_Code = p_Org_Code
                                       AND T1.c_Typeofapplicant = 'B')) Ss
                     GROUP BY Ss.Sz_Org_Code,
                              Ss.Sz_Loan_Account_No,
                              Ss.i_Reference_No,
                              Ss.Sz_Tranhead,
                              Ss.Sz_Trantype,
                              Ss.Head_Desc) T1
             GROUP BY T1.Sz_Org_Code,
                      T1.Lan,
                      T1.Tranhead,
                      T1.Sz_Trantype,
                      T1.Head_Desc
            UNION
            SELECT La.Sz_Org_Code,
                   La.Sz_Loan_Account_No,
                   Nvl(Pkg_Penal_Interest.Get_Penal_Computed_Amt(La.Sz_Org_Code,
                                                                 La.Sz_Loan_Account_No,
                                                                 1,
                                                                 NULL,
                                                                 NULL,
                                                                 Pkg_General_Services.Get_Business_Date(La.Sz_Org_Code),
                                                                 NULL,
                                                                 NULL,
                                                                 'CHG'),
                       0) Accountdue,
                   NULL,
                   Nvl(Pkg_Penal_Interest.Get_Penal_Computed_Amt(La.Sz_Org_Code,
                                                                 La.Sz_Loan_Account_No,
                                                                 1,
                                                                 NULL,
                                                                 NULL,
                                                                 Pkg_General_Services.Get_Business_Date(La.Sz_Org_Code),
                                                                 NULL,
                                                                 NULL,
                                                                 'TAX'),
                       0) Tax,
                   'PENAL_CHRG',
                   'PENAL_CHRG - Penal Accrued',
                   Nvl(Pkg_Penal_Interest.Get_Penal_Computed_Amt(La.Sz_Org_Code,
                                                                 La.Sz_Loan_Account_No,
                                                                 1,
                                                                 NULL,
                                                                 NULL,
                                                                 Pkg_General_Services.Get_Business_Date(La.Sz_Org_Code),
                                                                 NULL,
                                                                 NULL,
                                                                 NULL),
                       0) Total_Amt,
                   'FEE',
                   Nvl(Pkg_Penal_Interest.Get_Penal_Computed_Amt(La.Sz_Org_Code,
                                                                 La.Sz_Loan_Account_No,
                                                                 1,
                                                                 NULL,
                                                                 NULL,
                                                                 Pkg_General_Services.Get_Business_Date(La.Sz_Org_Code),
                                                                 NULL,
                                                                 NULL,
                                                                 'TAX'),
                       0) Tax1,
                   NULL
              FROM t_Lms_Loan_Account La
             WHERE La.Sz_Org_Code = p_Org_Code
               AND La.c_Account_Status <> 'C'
               AND La.Sz_Loan_Account_No IN
                   (SELECT T1.Sz_Loan_Account_No
                      FROM t_Lms_Loan_References T1
                     WHERE (T1.Sz_Customer_No = p_Loan_Account_No OR
                           T1.Sz_Loan_Account_No = p_Loan_Account_No)
                       AND T1.Sz_Org_Code = p_Org_Code
                       AND T1.c_Typeofapplicant = 'B')
               AND 'Y' =
                   (SELECT Cp.Sz_Value
                      FROM m_Lms_Condition_Parameter Cp
                     WHERE Cp.Sz_Org_Code = p_Org_Code
                       AND Cp.Sz_Condition = 'PENAL_BOOKING_ON_TRANSACTION')
               AND Nvl(Pkg_Penal_Interest.Get_Penal_Computed_Amt(La.Sz_Org_Code,
                                                                 La.Sz_Loan_Account_No,
                                                                 1,
                                                                 NULL,
                                                                 NULL,
                                                                 Pkg_General_Services.Get_Business_Date(La.Sz_Org_Code),
                                                                 NULL),
                       0) > 0) k;
  EXCEPTION
    WHEN OTHERS THEN
      p_Retmsg := Substr(SQLERRM, 1, 2000);
  END Prc_Lms_Bulk_Dre_Extvalue;
  FUNCTION Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  IN VARCHAR2,
                                   p_Tran_Type IN VARCHAR2,
                                   p_Err_Code  IN VARCHAR2,
                                   p_File_Name IN VARCHAR2) RETURN VARCHAR2 IS
    m_Err_Msg VARCHAR2(4000);
  BEGIN
    SELECT '###ERROR:' || e.Sz_Err_Msg
      INTO m_Err_Msg
      FROM m_Lms_Genbulk_Tran_Error e
     WHERE e.Sz_Org_Code = p_Org_Code
       AND e.Sz_Tran_Type = p_Tran_Type
       AND e.Sz_Err_Code = p_Err_Code;
    RETURN m_Err_Msg;
  EXCEPTION
    WHEN OTHERS THEN
      m_Err_Msg := 'Error Occured in Error message extract for Tran Type:' ||
                   p_Tran_Type || ' and file name:' || p_File_Name ||
                   Substr(SQLERRM, 1, 2000);
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.FUN_LMS_BULK_GEN_ERRMSG',
                                                    p_Errmsg   => m_Err_Msg);
  END Fun_Lms_Bulk_Gen_Errmsg;
  PROCEDURE Prc_Lms_Bulk_Setup_Val(p_Org_Code  VARCHAR2,
                                   p_Filename  IN VARCHAR2,
                                   p_Tran_Type IN VARCHAR2,
                                   p_level in varchar2 default null,
                                   p_Retmsg    OUT VARCHAR2) IS
    m_Retmsg VARCHAR2(4000);
    TYPE m_Tran_Data IS TABLE OF VARCHAR2(4000);
    m_Tran_Table        m_Tran_Data := m_Tran_Data();
    m_Tran_Column       m_Tran_Data := m_Tran_Data();
    m_Transaction_Table m_Lms_Bulk_Header.Sz_Tran_Table%TYPE;
    m_Str               VARCHAR2(4000);
    m_err_col VARCHAR2(4000);
    --CMN_VEW_BANKBRANCH_MASTER
  BEGIN
    SELECT h.Sz_Tran_Table, d.Sz_Tran_Api_Parameter BULK COLLECT
      INTO m_Tran_Table, m_Tran_Column
      FROM m_Lms_Bulk_Header h, m_Lms_Bulk_Details d
     WHERE h.Sz_Org_Code = d.Sz_Org_Code
       AND h.Sz_Transaction_Type = d.Sz_Transaction_Type
       AND h.Sz_Org_Code = p_Org_Code
       AND h.Sz_Transaction_Type = p_Tran_Type
     ORDER BY d.i_Parameter_Seq;
    if p_level='LEVEL1' then
       m_err_col:='Sz_ErrMsg';
    else
      m_err_col:='Sz_Stage2_Err';
    end if;  
    m_Transaction_Table := m_Tran_Table(1);
    m_Str               := 'UPDATE ' || m_Transaction_Table ||
                           ' SET '||m_err_col||' = NULL
     WHERE Sz_Org_Code = ''' || p_Org_Code || '''
       AND Sz_Filename = ''' || p_Filename || '''';
    EXECUTE IMMEDIATE m_Str;
    IF m_Tran_Column.Count > 0 THEN
      FOR Rec IN m_Tran_Column.First .. m_Tran_Column.Last LOOP
        m_Str := '';
        ----DRE---
        IF m_Tran_Column(Rec) = 'SZ_INSTRUMENT_TYPE' THEN
          ----lookups
          m_Retmsg := '###ERROR:Instrument Type(SZ_INSTRUMENT_TYPE) not matched with Lookups:INSTRUMENT_TYPE';
          m_Str    := 'UPDATE ' || m_Transaction_Table || ' t
             SET '||m_err_col||' = '||m_err_col||' ||''' ||
                      m_Retmsg || '''
           WHERE t.Sz_Org_Code = ''' || p_Org_Code || '''
           AND t.Sz_Filename = ''' || p_Filename || '''
                        AND t.Sz_Errmsg IS NULL
           and NOT EXISTS
           (SELECT v.Sz_Lookup_Code
                    FROM m_Lms_Lookup v
                   WHERE v.Sz_Org_Code = ''' ||
                      p_Org_Code || '''
                     AND Sz_Lookup_Type_Code = ''INSTRUMENT_TYPE''
                     AND v.Sz_Lookup_Code = UPPER(t.Sz_Instrument_Type))';
        ELSIF m_Tran_Column(Rec) = 'SZ_INSTRUMENT_LOC' THEN
          m_Retmsg := '###ERROR:Instrument Location(SZ_INSTRUMENT_LOC) not matched with Lookups:CHEQUE_LOCATION';
          m_Str    := 'UPDATE ' || m_Transaction_Table || ' t
             SET '||m_err_col||' = '||m_err_col||' ||''' ||
                      m_Retmsg || '''
           WHERE t.Sz_Org_Code = ''' || p_Org_Code || '''
             AND t.Sz_Filename = ''' || p_Filename || '''
             AND t.Sz_Instrument_Loc IS NOT NULL
                          AND t.Sz_Errmsg IS NULL
             AND NOT EXISTS
           (SELECT v.Sz_Lookup_Code
                    FROM m_Lms_Lookup v
                   WHERE v.Sz_Org_Code = ''' ||
                      p_Org_Code || '''
                     AND Sz_Lookup_Type_Code = ''CHEQUE_LOCATION''
                     AND v.Sz_Lookup_Code = UPPER(t.Sz_Instrument_Loc))';
        ELSIF m_Tran_Column(Rec) = 'SZ_ACCOUNT_TYPE' THEN
          m_Retmsg := '###ERROR:Account Type(SZ_ACCOUNT_TYPE) not matched with Lookups:ACCOUNT_TYPE';
          m_Str    := 'UPDATE ' || m_Transaction_Table || ' t
             SET '||m_err_col||' = '||m_err_col||' ||''' ||
                      m_Retmsg || '''
           WHERE t.Sz_Org_Code = ''' || p_Org_Code || '''
             AND t.Sz_Filename = ''' || p_Filename || '''
             AND t.Sz_Account_Type IS NOT NULL
                          AND t.Sz_Errmsg IS NULL
             AND NOT EXISTS
           (SELECT v.Sz_Lookup_Code
                    FROM m_Lms_Lookup v
                   WHERE v.Sz_Org_Code = ''' ||
                      p_Org_Code || '''
                     AND Sz_Lookup_Type_Code = ''ACCOUNT_TYPE''
                     AND v.Sz_Lookup_Code = UPPER(t.Sz_Account_Type))';
        ELSIF m_Tran_Column(Rec) = 'SZ_IFSC_CODE' THEN
          m_Retmsg := '###ERROR:IFSC CODE(SZ_IFSC_CODE) not matched with MASTER:CMN_VEW_BANKBRANCH_MASTER';
          m_Str    := 'UPDATE ' || m_Transaction_Table || ' t
             SET '||m_err_col||' = '||m_err_col||' ||''' ||
                      m_Retmsg || '''
           WHERE t.Sz_Org_Code = ''' || p_Org_Code || '''
             AND t.Sz_Filename = ''' || p_Filename || '''
             AND t.SZ_IFSC_CODE IS NOT NULL
                          AND t.Sz_Errmsg IS NULL
             AND NOT EXISTS
           (SELECT b.Sz_Ifsc_Code
                    FROM Cmn_Vew_Bankbranch_Master b
                   WHERE b.sz_org_code = ''' ||
                      p_Org_Code || '''
                     AND b.Sz_Ifsc_Code = UPPER(t.SZ_IFSC_CODE))';
        ELSIF m_Tran_Column(Rec) = 'SZ_BANK_CODE' THEN
          ----MASTER
          m_Retmsg := '###ERROR:BANK CODE(SZ_BANK_CODE) not matched with MASTER:CMN_VEW_BANKBRANCH_MASTER';
          m_Str    := 'UPDATE ' || m_Transaction_Table || ' t
             SET '||m_err_col||' = '||m_err_col||' ||''' ||
                      m_Retmsg || '''
           WHERE t.Sz_Org_Code = ''' || p_Org_Code || '''
             AND t.Sz_Filename = ''' || p_Filename || '''
             AND t.Sz_Bank_Code IS NOT NULL
                          AND t.Sz_Errmsg IS NULL
             AND NOT EXISTS
           (SELECT b.Sz_Bank_Code
                    FROM Cmn_Vew_Bankbranch_Master b
                   WHERE b.sz_org_code = ''' ||
                      p_Org_Code || '''
                     AND B.Sz_Ifsc_Code= UPPER(t.SZ_IFSC_CODE)
                     AND b.Sz_Bank_Code = UPPER(t.Sz_Bank_Code))';
        ELSIF m_Tran_Column(Rec) = 'SZ_BANK_BRANCH_CODE' THEN
          m_Retmsg := '###ERROR:BANK BRANCH CODE(SZ_BANK_BRANCH_CODE) not matched with MASTER:CMN_VEW_BANKBRANCH_MASTER';
          m_Str    := 'UPDATE ' || m_Transaction_Table || ' t
             SET '||m_err_col||' = '||m_err_col||' ||''' ||
                      m_Retmsg || '''
           WHERE t.Sz_Org_Code = ''' || p_Org_Code || '''
             AND t.Sz_Filename =''' || p_Filename || '''
             AND t.Sz_Bank_Branch_Code IS NOT NULL
                          AND t.Sz_Errmsg IS NULL
             AND NOT EXISTS
           (SELECT b.SZ_BANKBRANCH_CODE
                    FROM Cmn_Vew_Bankbranch_Master b
                   WHERE b.sz_org_code =''' ||
                      p_Org_Code || '''
                     AND B.Sz_Ifsc_Code= UPPER(t.SZ_IFSC_CODE)
                     AND b.Sz_Bank_Code = UPPER(t.Sz_Bank_Code)
                     AND b.Sz_Bankbranch_Code = UPPER(t.Sz_Bank_Branch_Code))';
        ELSIF m_Tran_Column(Rec) = 'SZ_DEPOSIT_BANK_CODE' THEN
          m_Retmsg := '###ERROR:DEPOSIT BANK CODE(SZ_DEPOSIT_BANK_CODE) not matched with MASTER:V_DEPOSIT_BUBANK_MASTER';
          m_Str    := 'UPDATE ' || m_Transaction_Table || ' t
             SET '||m_err_col||' = '||m_err_col||' ||''' ||
                      m_Retmsg || '''
           WHERE t.Sz_Org_Code = ''' || p_Org_Code || '''
             AND t.Sz_Filename = ''' || p_Filename || '''
             AND t.Sz_Deposit_Bank_Code IS NOT NULL
             AND t.Sz_Errmsg IS NULL
             AND NOT EXISTS
           (SELECT v.Sz_Dpbank_Code
                    FROM v_Deposit_Bubank_Master v
                   WHERE v.Sz_Org_Code =''' ||
                      p_Org_Code || '''
                    AND upper(v.Sz_Dpbank_Code) = UPPER(t.Sz_Deposit_Bank_Code))';
         
          -----DRE END----
          ----RESCHEDULE----
        ELSIF m_Tran_Column(Rec) = 'C_REPAY_FREQ' THEN
          m_Retmsg := '###ERROR:Repayment Frequency (c_Repay_Freq) not matched with Lookups:REPAYMENT_FREQUENCY';
          m_Str    := 'UPDATE ' || m_Transaction_Table || ' t
               SET '||m_err_col||' = '||m_err_col||' ||''' ||
                      m_Retmsg || '''
             WHERE NOT EXISTS (SELECT v.Sz_Lookup_Code
                      FROM m_Lms_Lookup v
                     WHERE v.Sz_Org_Code = ''' ||
                      p_Org_Code || '''
                       AND Sz_Lookup_Type_Code = ''REPAYMENT_FREQUENCY''
                       AND v.Sz_Lookup_Code = t.c_Repay_Freq)
               AND t.Sz_Errmsg IS NULL
               AND t.Sz_Filename =''' || p_Filename || '''';
        ELSIF m_Tran_Column(Rec) = 'SZ_REASON' THEN
          m_Retmsg := '###ERROR:Reason (SZ_REASON) not matched with Lookup:V_LMS_LOOKUP_RESCHEDULE_REASON';
          m_Str    := 'UPDATE ' || m_Transaction_Table || ' t
       SET '||m_err_col||' = '||m_err_col||' ||''' ||
                      m_Retmsg || '''
     WHERE NOT EXISTS (SELECT v.Code
              FROM v_Lms_Lookup_Reschedule_Reason v
             WHERE v.Sz_Org_Code = ''' || p_Org_Code || '''
               AND v.Code = UPPER(t.Sz_Reason))
       AND t.Sz_Errmsg IS NULL
       AND t.Sz_Filename = ''' || p_Filename || '''';
        ELSIF m_Tran_Column(Rec) = 'C_CHANGE_FACTOR' THEN
          m_Retmsg := '###ERROR:WHAT TO CALCULATE(C_CHANGE_FACTOR) not matched with Fixed Values:Installment-I,Tenor-T';
          m_Str    := 'UPDATE ' || m_Transaction_Table || ' t
       SET '||m_err_col||' = '||m_err_col||'  ||''' ||
                      m_Retmsg || '''
     WHERE Sz_Org_Code = ''' || p_Org_Code || '''
       AND c_Change_Factor NOT IN (''I'', ''T'')
       AND t.Sz_Errmsg IS NULL
       AND t.Sz_Filename = ''' || p_Filename || '''';
        ELSIF m_Tran_Column(Rec) = 'I_CYCLEDAY' THEN
          m_Retmsg := '###ERROR:CYCLE DATE(I_CYCLEDAY) not matched with Master Values:';
          m_Str    := 'UPDATE ' || m_Transaction_Table || ' K
       SET '||m_err_col||' = '||m_err_col||'  ||''' ||
                      m_Retmsg ||
                      '''||
                           (SELECT Listagg(Cd, '','') Within GROUP(ORDER BY Cd)
                              FROM (SELECT DISTINCT t.Icycday Cd
                                      FROM TABLE(Fn_Evlbilngcyc(''' ||
                      p_Org_Code || ''',
                                                                k.Sz_Loan_Account_No)) t))
     WHERE Sz_Org_Code = ''' || p_Org_Code || '''
       AND i_Cycleday IS NOT NULL
       AND k.Sz_Errmsg IS NULL
       AND k.Sz_Filename = ''' || p_Filename || '''
       AND NOT EXISTS
     (SELECT DISTINCT t.Icycday Cd
              FROM TABLE(Fn_Evlbilngcyc(''' ||
                      p_Org_Code ||
                      ''', k.Sz_Loan_Account_No)) t
             WHERE t.Icycday = k.i_Cycleday)';
        END IF;
        IF m_Str IS NOT NULL THEN
          EXECUTE IMMEDIATE m_Str;
        END IF;
      END LOOP;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      p_Retmsg := 'Error Occured in Setup for ' || p_Tran_Type ||
                  ' and file name:' || p_Filename || ':' ||
                  Substr(SQLERRM, 1, 2000);
  END Prc_Lms_Bulk_Setup_Val;
  PROCEDURE Prc_Lms_Bulk_Common(p_Org_Code      VARCHAR2,
                                p_Business_Date DATE DEFAULT NULL,
                                p_Status        IN VARCHAR2,
                                p_Tran_Type     IN VARCHAR2) IS
    TYPE Type_File_Name IS TABLE OF t_Lms_Bulk_Tran_Details.Sz_File_Name%TYPE;
    Rec_File_Name Type_File_Name := Type_File_Name();
    m_File_Name   VARCHAR2(4000);
    m_Outstr      VARCHAR2(4000);
    Err_Resch_Process EXCEPTION;
    m_Tot2_Cnt      NUMBER := 0;
    m_Err2_Cnt      NUMBER := 0;
    m_Batch_Status  t_Lms_Bulk_Tran_Details.c_Batch_Status%TYPE;
    m_Retmsg        VARCHAR2(4000);
    m_Str           VARCHAR2(4000);
    m_Str_Proc      VARCHAR2(4000);
    m_Tran_Table    m_Lms_Bulk_Header.Sz_Tran_Table%TYPE;
    m_Procedure     m_Lms_Bulk_Header.Sz_Transaction_Api%TYPE;
    m_Business_Date DATE := Trunc(Fun_Getbusinessdate(p_Org_Code));
  BEGIN
    SELECT Sz_File_Name BULK COLLECT
      INTO Rec_File_Name
      FROM t_Lms_Bulk_Tran_Details t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND Sz_Transaction_Type = p_Tran_Type
       AND t.c_Checker_Status = p_Status -- IN ('LS', 'IS')
       AND trim(t.c_Batch_Status) IS NULL --AND T.C_BATCH_STATUS NOT IN ('P','R','C')
       AND Trunc(t.Dt_Batch_Create) = m_Business_Date --Trunc(p_Business_Date)
    --and sz_file_name='RESCHEDULE_BULK_SYSADMIN_15022017_1261_i.xls'
     ORDER BY Dt_Upload;
    SELECT h.Sz_Tran_Table, h.Sz_Transaction_Api
      INTO m_Tran_Table, m_Procedure
      FROM m_Lms_Bulk_Header h
     WHERE h.Sz_Org_Code = p_Org_Code
       AND h.Sz_Transaction_Type = p_Tran_Type;
    IF Rec_File_Name.Count > 0 THEN
      FOR k IN Rec_File_Name.First .. Rec_File_Name.Last LOOP
        m_File_Name := Rec_File_Name(k);
        UPDATE t_Lms_Bulk_Tran_Details t
           SET t.c_Batch_Status = 'P'
         WHERE t.Sz_Org_Code = p_Org_Code
           AND t.Sz_Transaction_Type = p_Tran_Type
           AND t.Sz_File_Name = m_File_Name
           AND Trunc(t.Dt_Batch_Create) = m_Business_Date; --Trunc(p_Business_Date);
        COMMIT;
        m_Str := 'UPDATE ' || m_Tran_Table || '
           SET Sz_Stage2_Err = NULL
         WHERE Sz_Org_Code = ''' || p_Org_Code || '''
           AND Sz_Filename = ''' || m_File_Name || '''';
        EXECUTE IMMEDIATE m_Str;
        
        BEGIN
        m_Str_Proc := 'BEGIN Pkg_Lms_Bulk_Operation.' || m_Procedure ||
                      '(:p_Org_Code ,:m_File_Name,:p_Business_Date,:m_Outstr); END;';
        EXECUTE IMMEDIATE m_Str_Proc
          USING IN p_Org_Code, IN m_File_Name, IN Trunc(m_Business_Date), OUT m_Outstr;
       /*  m_Str_Proc := 'DECLARE m_Outstr VARCHAR2(4000); BEGIN Pkg_Lms_Bulk_Operation.' || m_Procedure ||
                      '('''||p_Org_Code||''','''||m_File_Name||''','''||Trunc(m_Business_Date)||''',p_Outstr=>m_Outstr); END;';
         EXECUTE IMMEDIATE m_Str_Proc;
         m_Outstr:='T';*/
        EXCEPTION
          WHEN OTHERS THEN
             m_Retmsg := 'Error Occured in Upload process for Tran Type:' ||
                  p_Tran_Type || ' and file name:' || m_File_Name ||
                  Substr(SQLERRM, 1, 2000);
           Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => m_Str_Proc,
                                                    p_Errmsg   => m_Retmsg);
        END;
        IF m_Outstr = 'T' THEN
          m_Str := 'SELECT COUNT(1)
            FROM ' || m_Tran_Table ||
                   ' WHERE Sz_Org_Code =''' || p_Org_Code || '''
             AND Sz_Filename =''' || m_File_Name || '''
             AND Sz_Stage2_Err IS NOT NULL';
          EXECUTE IMMEDIATE m_Str
            INTO m_Err2_Cnt;
          m_Str := 'SELECT COUNT(1)
            FROM ' || m_Tran_Table ||
                   ' WHERE Sz_Org_Code =''' || p_Org_Code || '''
             AND Sz_Filename =''' || m_File_Name || '''
             AND Sz_Errmsg IS NULL';
          EXECUTE IMMEDIATE m_Str
            INTO m_Tot2_Cnt;
          IF m_Err2_Cnt = 0 THEN
            m_Batch_Status := 'C';
          ELSIF m_Err2_Cnt = m_Tot2_Cnt THEN
            m_Batch_Status := 'R';
          ELSE
            m_Batch_Status := 'R';
          END IF;
          UPDATE t_Lms_Bulk_Tran_Details t
             SET t.c_Batch_Status   = m_Batch_Status,
                 t.c_Checker_Status = m_Batch_Status,--'C'--ISSUE FIXED 144280
                 t.c_Maker_Status   = 'C'
           WHERE t.Sz_Org_Code = p_Org_Code
             AND t.Sz_Transaction_Type = p_Tran_Type
             AND t.Sz_File_Name = m_File_Name
             AND Trunc(t.Dt_Batch_Create) = Trunc(m_Business_Date);
        ELSE
          m_Retmsg := 'Error Occured in execution process for Tran Type-' ||
                      p_Tran_Type || ':file name-' || m_File_Name ||
                      ':Procedure-' || m_Procedure || ':' ||
                      Substr(SQLERRM, 1, 1500);
          Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                        p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Common',
                                                        p_Errmsg   => m_Retmsg);
        END IF;
      END LOOP;
    END IF;
    --p_Retmsg := 'T';
  EXCEPTION
    WHEN OTHERS THEN
      m_Retmsg := 'Error Occured in Upload process for Tran Type:' ||
                  p_Tran_Type || ' and file name:' || m_File_Name ||
                  Substr(SQLERRM, 1, 2000);
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Common',
                                                    p_Errmsg   => m_Retmsg);
  END Prc_Lms_Bulk_Common;
  PROCEDURE Prc_Lms_Bulk_Resch_Varitions(p_Org_Code        IN VARCHAR2,
                                         p_File_Name       IN VARCHAR2,
                                         p_Loan_Account_No IN VARCHAR2,
                                         p_Srno            IN VARCHAR2,
                                         p_Tenor           IN NUMBER,
                                         p_Out_Xml         OUT VARCHAR2,
                                         p_Ret_Msg         OUT VARCHAR2) IS
    ---BALLOON 
    m_Balloon_Cnt     NUMBER := 0;
    m_Ballon_Err      CHAR(1) := 'N';
    m_Binstvalue      VARCHAR2(4000);
    m_Binstno         NUMBER := 0; --VARCHAR2(4000);
    m_Binstno1        NUMBER := 0; --VARCHAR2(4000);
    m_Binstnoxml      VARCHAR2(4000);
    m_Bvalue          NUMBER := 0; --VARCHAR2(4000);
    m_Bvaluexml       VARCHAR2(4000);
    m_Ballon_Basis    t_Lms_Genbulk_Reschedule.Sz_Ballon_Basis%TYPE;
    m_Ballon_Type     t_Lms_Genbulk_Reschedule.Sz_Ballon_Type%TYPE;
    m_Binstallment_No t_Lms_Genbulk_Reschedule.i_Binstallment_No%TYPE;
    m_Ballon_Value    t_Lms_Genbulk_Reschedule.f_Ballon_Value%TYPE;
    m_Ballon_Adj      t_Lms_Genbulk_Reschedule.Sz_Ballon_Adj%TYPE;
    ---end BALLOON 
    --STEP
    m_Step_Cnt           NUMBER := 0;
    m_Step_Err           CHAR(1) := 'N';
    m_Stinstfrom         NUMBER := 0; --VARCHAR2(4000);
    m_Stinstfrom1        NUMBER := 0; --VARCHAR2(4000);
    m_Stinstfromxml      VARCHAR2(4000);
    m_Stinstto           NUMBER := 0; --VARCHAR2(4000);
    m_Stinstto1          NUMBER := 0; --VARCHAR2(4000);
    m_Stinsttoxml        VARCHAR2(4000);
    m_Stvalue            NUMBER := 0; --VARCHAR2(4000);
    m_Stvaluexml         VARCHAR2(4000);
    m_Stinstvalue        VARCHAR2(4000);
    m_Tenor              t_Lms_Genbulk_Reschedule.i_Tenor%TYPE;
    m_Step_Type          t_Lms_Genbulk_Reschedule.Sz_Step_Type%TYPE;
    m_Step_Basis         t_Lms_Genbulk_Reschedule.Sz_Step_Basis%TYPE;
    m_Step_Adj           t_Lms_Genbulk_Reschedule.Sz_Step_Adj%TYPE;
    m_Step_Prinrec       t_Lms_Genbulk_Reschedule.Sz_Step_Prinrec%TYPE;
    m_Step_Prinrec_Type  t_Lms_Genbulk_Reschedule.Sz_Step_Prinrec_Type%TYPE;
    m_Stinstallment_From t_Lms_Genbulk_Reschedule.i_Stinstallment_From%TYPE;
    m_Stinstallment_To   t_Lms_Genbulk_Reschedule.i_Stinstallment_To%TYPE;
    m_Step_Value         t_Lms_Genbulk_Reschedule.f_Step_Value%TYPE;
    --END STEP
    --SKIP
    m_Skip_Cnt           NUMBER := 0;
    m_Skip_Err           CHAR(1) := 'N';
    m_Skinstfrom         NUMBER := 0; --VARCHAR2(4000);
    m_Skinstfrom1        NUMBER := 0; --VARCHAR2(4000);
    m_Skinstfromxml      VARCHAR2(4000);
    m_Skinstto           NUMBER := 0; --VARCHAR2(4000);
    m_Skinstto1          NUMBER := 0; --VARCHAR2(4000);
    m_Skinsttoxml        VARCHAR2(4000);
    m_Pxml               VARCHAR2(4000);
    m_Sxml               VARCHAR2(4000);
    m_Skip_Int_Cap       VARCHAR2(4000);
    m_Skinstvalue        VARCHAR2(4000);
    m_Skip_Int_Charge    t_Lms_Genbulk_Reschedule.Sz_Skip_Int_Charge%TYPE;
    m_Skip_Int_Coll      t_Lms_Genbulk_Reschedule.Sz_Skip_Int_Coll%TYPE;
    m_Skip_Adj           t_Lms_Genbulk_Reschedule.Sz_Skip_Adj%TYPE;
    m_Skip_Int_Pay       VARCHAR2(4000);
    m_Skip_Partial_Flag  t_Lms_Genbulk_Reschedule.c_Skip_Partial_Flag%TYPE;
    m_Skip_Part_Pay      t_Lms_Genbulk_Reschedule.Sz_Skip_Part_Pay%TYPE;
    m_Skip_Per_Amt       t_Lms_Genbulk_Reschedule.f_Skip_Per_Amt%TYPE;
    m_Skinstallment_From t_Lms_Genbulk_Reschedule.i_Skinstallment_From%TYPE;
    m_Skinstallment_To   t_Lms_Genbulk_Reschedule.i_Skinstallment_To%TYPE;
    --END SKIP
    m_Retmsg         VARCHAR2(4000);
    m_Pipe           VARCHAR2(100);
    m_Loan_Str       VARCHAR2(4000);
    m_Xml            VARCHAR2(4000) := '';
    m_Variation_Flag t_Lms_Genbulk_Reschedule.c_Variation_Flag%TYPE;
    m_From_Insto     NUMBER := 0;
  BEGIN
    m_Loan_Str := '<root LoanAccno=''' || p_Loan_Account_No ||
                  '''><tranche tno=''1'' />';
    SELECT Fun_Get_Next_Installmentno(p_Org_Code,
                                      p_Loan_Account_No,
                                      '1',
                                      To_Date(Fun_Getbusinessdate(p_Org_Code),
                                              'DD/MM/RRRR')) Firstinstdt
      INTO m_From_Insto
      FROM Dual;
    SELECT Nvl(c_Variation_Flag, 'VR')
      INTO m_Variation_Flag
      FROM t_Lms_Genbulk_Reschedule t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Loan_Account_No = p_Loan_Account_No
       AND t.Row_Srno = p_Srno
       AND t.Sz_Filename = p_File_Name
       AND t.Sz_Errmsg IS NULL
       AND t.Sz_Stage2_Err IS NULL;
    IF m_Variation_Flag = 'VR' THEN
      p_Out_Xml := '';
      p_Ret_Msg := 'T';
      RETURN;
    END IF;
    ---BALLOON 
    IF m_Variation_Flag = 'BL' THEN
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = Sz_Stage2_Err ||
                               '###ERROR:Invalid Balloon Basis'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Row_Srno = p_Srno
         AND t.Sz_Filename = p_File_Name
         AND t.Sz_Errmsg IS NULL
         AND Sz_Ballon_Basis IS NOT NULL
         AND Upper(t.Sz_Ballon_Basis) NOT IN ('A', 'P'); --(A-AMOUNT/P-PERCENTAGE)
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = Sz_Stage2_Err ||
                               '###ERROR:Invalid Balloon Type'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Row_Srno = p_Srno
         AND t.Sz_Filename = p_File_Name
         AND t.Sz_Errmsg IS NULL
         AND Upper(t.Sz_Ballon_Type) NOT IN ('I', 'E'); --(I-INTERMITTENT/E-END OF TENOR)
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = Sz_Stage2_Err ||
                               '###ERROR:Invalid Balloon Ajustment'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Row_Srno = p_Srno
         AND t.Sz_Filename = p_File_Name
         AND t.Sz_Errmsg IS NULL
         AND Upper(t.Sz_Ballon_Adj) NOT IN ('1', '0'); -- (1-ADJUSTEMI/0-ADJUSTEDEMI)
      BEGIN
        SELECT Nvl(Sz_Ballon_Basis, ''),
               Sz_Ballon_Type,
               i_Binstallment_No,
               f_Ballon_Value,
               Sz_Ballon_Adj
          INTO m_Ballon_Basis,
               m_Ballon_Type,
               m_Binstallment_No,
               m_Ballon_Value,
               m_Ballon_Adj
          FROM t_Lms_Genbulk_Reschedule t
         WHERE t.Sz_Org_Code = p_Org_Code
           AND t.Sz_Filename = p_File_Name
           AND t.Sz_Loan_Account_No = p_Loan_Account_No
           AND t.Row_Srno = p_Srno
           AND t.Sz_Errmsg IS NULL
           AND t.Sz_Stage2_Err IS NULL;
      EXCEPTION
        WHEN OTHERS THEN
          m_Ballon_Err := 'Y';
      END;
      IF m_Ballon_Err = 'N' AND m_Ballon_Type = 'E' AND
         m_Binstallment_No IS NOT NULL THEN
        p_Ret_Msg := '###ERROR:Installment no. should be blank while balloon type is E(End of Tenor)';
        m_Xml     := '';
        RETURN;
      END IF;
      IF m_Ballon_Err = 'N' AND m_Ballon_Type = 'E' AND
         m_Ballon_Basis = 'P' --issue fixed 151742
          THEN
        p_Ret_Msg := '###ERROR:Percentage parameter not allowed while balloon type is E(End of Tenor)';
        m_Xml     := '';
        RETURN;
      END IF;
      IF m_Ballon_Err = 'N' AND m_Ballon_Type <> 'E' AND
         m_Binstallment_No IS NULL AND m_Ballon_Value IS NULL THEN
        p_Ret_Msg := '###ERROR:Installment no. should not be blank';
        m_Xml     := '';
        RETURN;
      END IF;
      IF m_Ballon_Err = 'N' THEN
        m_Pipe := Substr(m_Binstallment_No, Length(m_Binstallment_No));
        IF m_Pipe <> '|' THEN
          m_Binstallment_No := m_Binstallment_No || '|';
        END IF;
        m_Pipe := Substr(m_Ballon_Value, Length(m_Ballon_Value));
        IF m_Pipe <> '|' THEN
          m_Ballon_Value := m_Ballon_Value || '|';
        END IF;
        IF (Nvl(Regexp_Count(m_Binstallment_No, '[|]'), 0) <>
           Nvl(Regexp_Count(m_Ballon_Value, '[|]'), 0)) AND
           m_Ballon_Type <> 'E' THEN
          p_Ret_Msg := '###ERROR:Invalid data provided in Balloon Variations';
          m_Xml     := '';
          RETURN;
        END IF;
        IF Regexp_Replace(m_Binstallment_No, '[^0-9]') IS NULL AND
           m_Ballon_Type <> 'E' THEN
          p_Ret_Msg := '###ERROR:Installment No. is required in Balloon Variations';
          m_Xml     := '';
          RETURN;
        END IF;
        IF Regexp_Replace(m_Ballon_Value, '[^0-9]') IS NULL THEN
          p_Ret_Msg := '###ERROR:Value is required in Balloon Variations';
          m_Xml     := '';
          RETURN;
        END IF;
        m_Balloon_Cnt := Regexp_Count(m_Ballon_Value, '[|]');
        FOR k IN 1 .. m_Balloon_Cnt LOOP
          m_Binstno := Nvl(Regexp_Substr(m_Binstallment_No, '[^|]+', 1, k),
                           '');
          IF m_Binstno = 999999999 AND m_Ballon_Type <> 'E' THEN
            p_Ret_Msg := '###ERROR:Invalid Balloon Installment no.';
            m_Xml     := '';
            RETURN;
          END IF;
          m_Binstnoxml := m_Binstno;
          m_Bvalue     := Nvl(Regexp_Substr(m_Ballon_Value, '[^|]+', 1, k),
                              999999999);
          IF m_Bvalue = 999999999 THEN
            p_Ret_Msg := '###ERROR:Invalid Balloon Amount';
            m_Xml     := '';
            RETURN;
          END IF;
          --issue fixed 144876
          IF m_Ballon_Basis = 'P' THEN
            IF (m_Bvalue <= 0 OR m_Bvalue > 100) THEN
              p_Ret_Msg := '###ERROR:Balloon Percentage should be between 0 to 100%';
              m_Xml     := '';
              RETURN;
            END IF;
          END IF;
          --end 
          m_Bvaluexml := m_Bvalue;
          --newly added
          IF m_Binstno < m_From_Insto AND m_Ballon_Type <> 'E' THEN
            p_Ret_Msg := '###ERROR:Balloon Inst. No:' || m_Binstno ||
                         ' should be greater than next installment no:' ||
                         m_From_Insto;
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_From_Insto > p_Tenor THEN
            p_Ret_Msg := '###ERROR:Balloon Inst. No:' || m_Binstno ||
                         ' should be less than tenor:' || p_Tenor;
            m_Xml     := '';
            RETURN;
          END IF;
          IF (m_Binstno < m_From_Insto AND m_Binstno > p_Tenor) AND
             m_Ballon_Type <> 'E' THEN
            p_Ret_Msg := '###ERROR:Balloon Inst. No:' || m_Binstno ||
                         ' between ' || m_From_Insto || ' and ' || p_Tenor;
            m_Xml     := '';
            RETURN;
          END IF;
          --end
          ---COMPARING BALLON INSTALLMENT NO
          m_Binstno1 := Regexp_Substr(m_Binstallment_No, '[^|]+', 1, k + 1);
          IF m_Binstno1 IS NULL THEN
            m_Binstno  := Regexp_Substr(m_Binstallment_No, '[^|]+', 1, 1);
            m_Binstno1 := Regexp_Substr(m_Binstallment_No, '[^|]+', 1, k);
          END IF;
          IF m_Binstno1 <= m_Binstno AND m_Balloon_Cnt > 1 AND
             m_Ballon_Type <> 'E' THEN
            p_Ret_Msg := '###ERROR:Balloon Inst. No:' || m_Binstno1 ||
                         ' should be greater than the previous row:' ||
                         m_Binstno;
            m_Xml     := '';
            RETURN;
          END IF;
          --END
          m_Binstvalue := m_Binstvalue || '<balinfo instno=''' ||
                          m_Binstnoxml || ''' value=''' || m_Bvaluexml ||
                          ''' adjbal=''' || m_Ballon_Adj || '''/>';
        END LOOP;
        m_Xml := m_Loan_Str || '<balloon basis =''' || m_Ballon_Basis ||
                 ''' baltype = ''' || m_Ballon_Type || '''/>' ||
                 m_Binstvalue || '</root>';
      ELSE
        m_Xml := '';
      END IF;
    ELSE
      m_Xml := '';
    END IF;
    ---END BALLOON 
    --STEP
    IF m_Variation_Flag = 'ST' THEN
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = Sz_Stage2_Err || '###ERROR:Invalid STEP Type'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Row_Srno = p_Srno
         AND t.Sz_Filename = p_File_Name
         AND t.Sz_Errmsg IS NULL
         AND Upper(t.Sz_Step_Type) NOT IN ('U', 'D'); --(U-UP/D-DOWN)
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = Sz_Stage2_Err ||
                               '###ERROR:Invalid STEP Basis'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Row_Srno = p_Srno
         AND t.Sz_Filename = p_File_Name
         AND t.Sz_Errmsg IS NULL
         AND Sz_Step_Basis IS NOT NULL
         AND Upper(t.Sz_Step_Basis) NOT IN ('0', '1', '2', '3'); --(0-AMOUNT/1-PERCENT/2-INSTALLMENT/3-EQUATED PRINCIPLE)
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = Sz_Stage2_Err ||
                               '###ERROR:Invalid STEP Adjustment'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Row_Srno = p_Srno
         AND t.Sz_Filename = p_File_Name
         AND t.Sz_Errmsg IS NULL
         AND Upper(t.Sz_Step_Adj) NOT IN ('1', '0'); -- (1-ADJUSTEMI/0-ADJUSTEDEMI)
      ---stpPrinRec,stpPrinRecType need to know
      BEGIN
        SELECT Sz_Step_Type,
               Nvl(Sz_Step_Basis, ''),
               Sz_Step_Adj,
               Nvl(Sz_Step_Prinrec, 'N'),
               Nvl(Sz_Step_Prinrec_Type, ''),
               i_Stinstallment_From,
               i_Stinstallment_To,
               f_Step_Value,
               t.i_Tenor
          INTO m_Step_Type,
               m_Step_Basis,
               m_Step_Adj,
               m_Step_Prinrec,
               m_Step_Prinrec_Type,
               m_Stinstallment_From,
               m_Stinstallment_To,
               m_Step_Value,
               m_Tenor
          FROM t_Lms_Genbulk_Reschedule t
         WHERE t.Sz_Org_Code = p_Org_Code
           AND t.Sz_Filename = p_File_Name
           AND t.Sz_Loan_Account_No = p_Loan_Account_No
           AND t.Row_Srno = p_Srno
           AND t.Sz_Errmsg IS NULL
           AND t.Sz_Stage2_Err IS NULL;
      EXCEPTION
        WHEN OTHERS THEN
          m_Step_Err := 'Y';
      END;
      IF m_Step_Err = 'N' THEN
        m_Pipe := Substr(m_Stinstallment_From, Length(m_Stinstallment_From));
        IF m_Pipe <> '|' THEN
          m_Stinstallment_From := m_Stinstallment_From || '|';
        END IF;
        m_Pipe := Substr(m_Stinstallment_To, Length(m_Stinstallment_To));
        IF m_Pipe <> '|' THEN
          m_Stinstallment_To := m_Stinstallment_To || '|';
        END IF;
        m_Pipe := Substr(m_Step_Value, Length(m_Step_Value));
        IF m_Pipe <> '|' THEN
          m_Step_Value := m_Step_Value || '|';
        END IF;
        IF ((Nvl(Regexp_Count(m_Stinstallment_From, '[|]'), 0) <>
           Nvl(Regexp_Count(m_Stinstallment_To, '[|]'), 0) OR
           Nvl(Regexp_Count(m_Stinstallment_To, '[|]'), 0) <>
           Nvl(Regexp_Count(m_Step_Value, '[|]'), 0)) OR
           (m_Step_Prinrec IS NULL)) THEN
          p_Ret_Msg := '###ERROR:Invalid data provided in STEP Variations';
          m_Xml     := '';
          RETURN;
        END IF;
        IF Regexp_Replace(m_Stinstallment_From, '[^0-9]') IS NULL THEN
          p_Ret_Msg := '###ERROR:Installment From is required in STEP Variations';
          m_Xml     := '';
          RETURN;
        END IF;
        IF Regexp_Replace(m_Stinstallment_To, '[^0-9]') IS NULL THEN
          p_Ret_Msg := '###ERROR:Installment To is required in STEP Variations';
          m_Xml     := '';
          RETURN;
        END IF;
        IF Regexp_Replace(m_Step_Value, '[^0-9]') IS NULL THEN
          p_Ret_Msg := '###ERROR:Step Value is required in STEP Variations';
          m_Xml     := '';
          RETURN;
        END IF;
        m_Step_Cnt := Regexp_Count(m_Stinstallment_From, '[|]');
        FOR k IN 1 .. m_Step_Cnt LOOP
          m_Stinstfrom := Nvl(Regexp_Substr(m_Stinstallment_From,
                                            '[^|]+',
                                            1,
                                            k),
                              999999999);
          IF m_Stinstfrom = 999999999 THEN
            p_Ret_Msg := '###ERROR:Invalid STEP Installment from';
            m_Xml     := '';
            RETURN;
          END IF;
          m_Stinstfromxml := m_Stinstfrom;
          m_Stinstto      := Nvl(Regexp_Substr(m_Stinstallment_To,
                                               '[^|]+',
                                               1,
                                               k),
                                 999999999);
          IF m_Stinstto = 999999999 THEN
            p_Ret_Msg := '###ERROR:Invalid STEP Installment to';
            m_Xml     := '';
            RETURN;
          END IF;
          m_Stinsttoxml := m_Stinstto;
          m_Stvalue     := Nvl(Regexp_Substr(m_Step_Value, '[^|]+', 1, k),
                               999999999);
          IF m_Stvalue = 999999999 THEN
            p_Ret_Msg := '###ERROR:Invalid STEP value ';
            m_Xml     := '';
            RETURN;
          END IF;
          m_Stvaluexml := m_Stvalue;
          IF m_Tenor IS NOT NULL AND m_Stinstto > m_Tenor THEN
            p_Ret_Msg := '###ERROR:Inst. To should be less than ' ||
                         m_Tenor;
            m_Xml     := '';
            RETURN;
          END IF;
          ---newly added     
          IF m_Stinstfrom < m_From_Insto AND k = 1 THEN
            p_Ret_Msg := '###ERROR:Step Inst. From:' || m_Stinstfrom ||
                         ' should be greater than next installment no:' ||
                         m_From_Insto;
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_From_Insto > p_Tenor OR m_Stinstfrom > p_Tenor AND k = 1 THEN
            p_Ret_Msg := '###ERROR:Step Inst. from:' || m_Stinstfrom ||
                         ' should be less than tenor:' || p_Tenor;
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Stinstto > p_Tenor THEN
            p_Ret_Msg := '###ERROR:Step Inst. to:' || m_Stinstto ||
                         ' should be less than tenor:' || p_Tenor;
            m_Xml     := '';
            RETURN;
          END IF;
          --
          ---VALIDATIONS FRONTEND
          IF m_Stinstto = 0 THEN
            p_Ret_Msg := '###ERROR:Inst. To should be greater than zero';
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Stinstfrom = 0 THEN
            p_Ret_Msg := '###ERROR:Inst. From should be greater than zero';
            m_Xml     := '';
            RETURN;
          END IF;
          IF (m_Stinstto < 0 OR m_Stinstfrom < 0) THEN
            p_Ret_Msg := '###ERROR:Inst. From and Inst. To values should be positive integers in Step Installment';
            m_Xml     := '';
            RETURN;
          END IF;
          ---COMPARING STEP INSTALLMENT NO
          m_Stinstfrom1 := Regexp_Substr(m_Stinstallment_From,
                                         '[^|]+',
                                         1,
                                         k + 1);
          m_Stinstto1   := Regexp_Substr(m_Stinstallment_To,
                                         '[^|]+',
                                         1,
                                         k + 1);
          IF m_Stinstfrom1 IS NULL AND k > 1 THEN
            m_Stinstfrom1 := Regexp_Substr(m_Stinstallment_From,
                                           '[^|]+',
                                           1,
                                           k);
            m_Stinstfrom  := Regexp_Substr(m_Stinstallment_From,
                                           '[^|]+',
                                           1,
                                           1);
          END IF;
          IF m_Stinstto1 IS NULL AND k > 1 THEN
            m_Stinstto1 := Regexp_Substr(m_Stinstallment_To, '[^|]+', 1, k);
            m_Stinstto  := Regexp_Substr(m_Stinstallment_To, '[^|]+', 1, 1);
          END IF;
          IF m_Stinstfrom1 <= m_Stinstfrom THEN
            p_Ret_Msg := '###ERROR:Inst. From should be greater than Inst. From of previous row in STEP';
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Stinstto1 <= m_Stinstto THEN
            p_Ret_Msg := '###ERROR:Inst. To should be greater than Inst. To of previous row in STEP';
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Stinstto <= m_Stinstfrom THEN
            p_Ret_Msg := '###ERROR:Inst. To should be greater than Inst. From of previous row in STEP';
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Stinstto >= m_Stinstfrom1 THEN
            p_Ret_Msg := '###ERROR:Inst. From should be greater than Inst. To of previous row in STEP';
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Stinstto1 <= m_Stinstfrom THEN
            p_Ret_Msg := '###ERROR:Inst. To should be greater than Inst. From of previous row in STEP';
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Stinstto1 <= m_Stinstfrom1 THEN
            p_Ret_Msg := '###ERROR:Inst. To should be greater than Inst. From of previous row in STEP';
            m_Xml     := '';
            RETURN;
          END IF;
          ---END
          m_Stinstvalue := m_Stinstvalue || '<stepinfo stpty=''' ||
                           m_Step_Type || ''' instfrm=''' ||
                           m_Stinstfromxml || ''' instto=''' ||
                           m_Stinsttoxml || ''' stpbasis=''' ||
                           m_Step_Basis || ''' value=''' || m_Stvaluexml ||
                           ''' adjstep =''' || m_Step_Adj ||
                           ''' stpPrinRec=''' || m_Step_Prinrec ||
                           ''' stpPrinRecType=''' || m_Step_Prinrec_Type ||
                           '''/>';
        END LOOP;
        m_Xml := m_Loan_Str || '<step stptype=''Y''/>' || m_Stinstvalue ||
                 '</root>';
      ELSE
        m_Xml := '';
      END IF;
    END IF;
    --END STEP
    ----skip
    IF m_Variation_Flag = 'SK' THEN
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = Sz_Stage2_Err ||
                               '###ERROR:Invalid SKIP Interest Charge Option'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Row_Srno = p_Srno
         AND t.Sz_Filename = p_File_Name
         AND t.Sz_Errmsg IS NULL
         AND Sz_Skip_Int_Charge IS NOT NULL
         AND Upper(t.Sz_Skip_Int_Charge) NOT IN ('C', 'F'); -- (C-CHARGABLE/F-FREE)
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = Sz_Stage2_Err ||
                               '###ERROR:Invalid SKIP Interest Collection Option'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Row_Srno = p_Srno
         AND t.Sz_Filename = p_File_Name
         AND t.Sz_Errmsg IS NULL
         AND Sz_Skip_Int_Coll IS NOT NULL
         AND Upper(t.Sz_Skip_Int_Coll) NOT IN ('', 'S', 'A', 'L'); --  (NULL/S-SEPERATE/A-ACCUMULATE/L-CUMMULATE)
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = Sz_Stage2_Err ||
                               '###ERROR:Invalid SKIP Ajustment'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Row_Srno = p_Srno
         AND t.Sz_Filename = p_File_Name
         AND t.Sz_Errmsg IS NULL
         AND Upper(t.Sz_Skip_Adj) NOT IN ('0', '1'); --  (1-ADJUSTEMI/0-ADJUSTEDEMI)
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = Sz_Stage2_Err ||
                               '###ERROR:Invalid SKIP Partial Interest'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Row_Srno = p_Srno
         AND t.Sz_Filename = p_File_Name
         AND t.Sz_Errmsg IS NULL
         AND Upper(t.c_Skip_Partial_Flag) NOT IN ('Y', 'N'); -- (Y/N)
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = Sz_Stage2_Err ||
                               '###ERROR:Invalid SKIP Partial Payment'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Row_Srno = p_Srno
         AND t.Sz_Filename = p_File_Name
         AND t.Sz_Errmsg IS NULL
         AND c_Skip_Partial_Flag = 'Y'
            --         AND Upper(t.Sz_Skip_Part_Pay) NOT IN ('P', 'A'); -- (P-PERCENTANGE/A-AMOUNT)
         AND Upper(t.Sz_Skip_Part_Pay) NOT IN ('P'); -- (P-PERCENTANGE/A-AMOUNT)
      BEGIN
        SELECT Nvl(Sz_Skip_Int_Charge, ''),
               Nvl(Sz_Skip_Int_Coll, ''),
               Sz_Skip_Adj,
               Nvl(c_Skip_Partial_Flag, 'N'),
               Sz_Skip_Part_Pay,
               f_Skip_Per_Amt,
               i_Skinstallment_From,
               i_Skinstallment_To
          INTO m_Skip_Int_Charge,
               m_Skip_Int_Coll,
               m_Skip_Adj,
               m_Skip_Partial_Flag,
               m_Skip_Part_Pay,
               m_Skip_Per_Amt,
               m_Skinstallment_From,
               m_Skinstallment_To
          FROM t_Lms_Genbulk_Reschedule t
         WHERE t.Sz_Org_Code = p_Org_Code
           AND t.Sz_Filename = p_File_Name
           AND t.Sz_Loan_Account_No = p_Loan_Account_No
           AND t.Row_Srno = p_Srno
           AND t.Sz_Errmsg IS NULL
           AND t.Sz_Stage2_Err IS NULL;
      EXCEPTION
        WHEN OTHERS THEN
          m_Skip_Err := 'Y';
      END;
      IF m_Skip_Err = 'N' THEN
        m_Pipe := Substr(m_Skinstallment_From, Length(m_Skinstallment_From));
        IF m_Pipe <> '|' THEN
          m_Skinstallment_From := m_Skinstallment_From || '|';
        END IF;
        m_Pipe := Substr(m_Skinstallment_To, Length(m_Skinstallment_To));
        IF m_Pipe <> '|' THEN
          m_Skinstallment_To := m_Skinstallment_To || '|';
        END IF;
        ---CHECK PARTIAL SKIP
        IF /*m_Skip_Partial_Flag IS NOT NULL AND*/
         m_Skip_Partial_Flag = 'Y' THEN
          IF m_Skip_Part_Pay = 'Y' AND m_Skip_Part_Pay <> 'P' THEN
            p_Ret_Msg := '###ERROR:SKIP Partial Payment should be (P-PERCENTANGE) in case of Partial Skip';
            m_Xml     := '';
            RETURN;
            /*ELSIF m_Skip_Per_Amt IS NULL THEN
            p_Ret_Msg := '###ERROR:SKIP Percentage/Amount should not be null in case of Partial Skip';
            m_Xml     := '';
            RETURN;*/
          ELSIF m_Skip_Int_Coll IS NOT NULL AND
                m_Skip_Int_Coll NOT IN ('A', 'L') THEN
            p_Ret_Msg := '###ERROR:SKIP Interest Collection Option should be (A-ACCUMULATE/L-CUMMULATE)';
            m_Xml     := '';
            RETURN;
          ELSIF m_Skip_Int_Charge IS NOT NULL AND m_Skip_Int_Charge <> 'C' THEN
            p_Ret_Msg := '###ERROR:SKIP Interest Charge Option should be (C-CHARGABLE)';
            m_Xml     := '';
            RETURN;
          END IF;
          m_Pxml := ' intpartial=''Y'' intpartpay=''P'' intper=''' ||
                    m_Skip_Per_Amt || '''';
        ELSE
          m_Pxml := '';
        END IF;
        --intcap (M_SKIP_INT_CAP)
        --intpay (M_SKIP_INT_PAY)
        IF m_Skip_Int_Coll = 'S' THEN
          m_Skip_Int_Cap := 'N';
          m_Skip_Int_Pay := 'Y';
          -- <intrmskp instfrm='2' instto='3' intcap='N'(M_SKIP_INT_CAP)  intcharge='C' intcoll='S' adjskip='1' intpay ='Y'(M_SKIP_INT_PAY)/></root>
        ELSIF m_Skip_Int_Coll = 'C' THEN
          m_Skip_Int_Cap := 'Y';
          m_Skip_Int_Pay := 'N';
        ELSIF m_Skip_Int_Coll = 'A' AND (m_Skip_Partial_Flag IS NOT NULL AND
              m_Skip_Partial_Flag = 'Y') THEN
          m_Skip_Int_Cap := 'A';
          m_Skip_Int_Pay := 'Y';
        ELSIF m_Skip_Int_Coll = 'L' AND (m_Skip_Partial_Flag IS NOT NULL AND
              m_Skip_Partial_Flag = 'Y') THEN
          m_Skip_Int_Cap := 'C';
          m_Skip_Int_Pay := 'Y';
        END IF;
        IF m_Skip_Int_Charge = 'F' THEN
          m_Skip_Int_Cap  := 'N';
          m_Skip_Int_Pay  := 'N';
          m_Skip_Int_Coll := '';
        END IF;
        m_Sxml := ' intcap=''' || m_Skip_Int_Cap || '''  intcharge=''' ||
                  m_Skip_Int_Charge || ''' intcoll=''' || m_Skip_Int_Coll ||
                  ''' adjskip=''' || m_Skip_Adj || ''' intpay =''' ||
                  m_Skip_Int_Pay || '''';
        IF ((Nvl(Regexp_Count(m_Skinstallment_From, '[|]'), 0) <>
           Nvl(Regexp_Count(m_Skinstallment_To, '[|]'), 0)) OR
           ( /*m_Skip_Int_Charge IS NULL OR*/
            m_Skip_Adj IS NULL)) THEN
          p_Ret_Msg := '###ERROR:Invalid data provided in SKIP Variations';
          m_Xml     := '';
          RETURN;
        END IF;
        IF Regexp_Replace(m_Skinstallment_From, '[^0-9]') IS NULL THEN
          p_Ret_Msg := '###ERROR:Installment From is required in SKIP Variations';
          m_Xml     := '';
          RETURN;
        END IF;
        IF Regexp_Replace(m_Skinstallment_To, '[^0-9]') IS NULL THEN
          p_Ret_Msg := '###ERROR:Installment To is required in SKIP Variations';
          m_Xml     := '';
          RETURN;
        END IF;
        m_Skip_Cnt := Regexp_Count(m_Skinstallment_From, '[|]');
        FOR k IN 1 .. m_Skip_Cnt LOOP
          m_Skinstfrom := Nvl(Regexp_Substr(m_Skinstallment_From,
                                            '[^|]+',
                                            1,
                                            k),
                              999999999);
          IF m_Skinstfrom = 999999999 THEN
            p_Ret_Msg := '###ERROR:Invalid SKIP Installment from';
            m_Xml     := '';
            RETURN;
          END IF;
          m_Skinstfromxml := m_Skinstfrom;
          m_Skinstto      := Nvl(Regexp_Substr(m_Skinstallment_To,
                                               '[^|]+',
                                               1,
                                               k),
                                 999999999);
          IF m_Skinstto = 999999999 THEN
            p_Ret_Msg := '###ERROR:Invalid SKIP Installment to';
            m_Xml     := '';
            RETURN;
          END IF;
          m_Skinsttoxml := m_Skinstto;
          ---newly added     
          IF m_Skinstfrom < m_From_Insto THEN
            p_Ret_Msg := '###ERROR:SKIP Inst. From:' || m_Skinstfrom ||
                         ' should be greater than next installment no:' ||
                         m_From_Insto;
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_From_Insto > p_Tenor OR m_Skinstfrom > p_Tenor THEN
            p_Ret_Msg := '###ERROR:SKIP Inst. from:' || m_Skinstfrom ||
                         ' should be less than tenor:' || p_Tenor;
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Skinstto > p_Tenor THEN
            p_Ret_Msg := '###ERROR:SKIP Inst. to:' || m_Skinstto ||
                         ' should be less than tenor:' || p_Tenor;
            m_Xml     := '';
            RETURN;
          END IF;
          --
          ---VALIDATIONS FRONTEND
          IF (m_Skinstto < 0 OR m_Skinstfrom < 0) THEN
            p_Ret_Msg := '###ERROR:Inst. From and Inst. To values should be positive integers in SKIP Installment';
            m_Xml     := '';
            RETURN;
          END IF;
          ---COMPARING SKIP INSTALLMENT NO
          m_Skinstfrom1 := Regexp_Substr(m_Skinstallment_From,
                                         '[^|]+',
                                         1,
                                         k + 1);
          m_Skinstto1   := Regexp_Substr(m_Skinstallment_To,
                                         '[^|]+',
                                         1,
                                         k + 1);
          IF m_Skinstfrom1 IS NULL AND k > 1 THEN
            m_Skinstfrom1 := Regexp_Substr(m_Skinstallment_From,
                                           '[^|]+',
                                           1,
                                           k);
            m_Skinstfrom  := Regexp_Substr(m_Skinstallment_From,
                                           '[^|]+',
                                           1,
                                           1);
          END IF;
          IF m_Skinstto1 IS NULL THEN
            m_Skinstto1 := Regexp_Substr(m_Stinstallment_To, '[^|]+', 1, k);
            m_Skinstto  := Regexp_Substr(m_Stinstallment_To, '[^|]+', 1, 1);
          END IF;
          IF m_Skinstfrom1 <= m_Skinstfrom THEN
            p_Ret_Msg := '###ERROR:Inst. From should be greater than Inst. From of previous row in SKIP';
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Skinstto1 <= m_Skinstto THEN
            p_Ret_Msg := '###ERROR:Inst. To should be greater than Inst. To of previous row in SKIP';
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Skinstto <= m_Skinstfrom THEN
            p_Ret_Msg := '###ERROR:Inst. To should be greater than Inst. From of previous row in SKIP';
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Skinstto >= m_Skinstfrom1 THEN
            p_Ret_Msg := '###ERROR:Inst. From should be greater than Inst. To of previous row in SKIP';
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Skinstto1 <= m_Skinstfrom THEN
            p_Ret_Msg := '###ERROR:Inst. To should be greater than Inst. From of previous row in SKIP';
            m_Xml     := '';
            RETURN;
          END IF;
          IF m_Skinstto1 <= m_Skinstfrom1 THEN
            p_Ret_Msg := '###ERROR:Inst. To should be greater than Inst. From of previous row in SKIP';
            m_Xml     := '';
            RETURN;
          END IF;
          ---END
          m_Skinstvalue := m_Skinstvalue || '<intrmskp instfrm=''' ||
                           m_Skinstfromxml || ''' instto=''' ||
                           m_Skinsttoxml || '''' || m_Sxml || m_Pxml || '/>';
        END LOOP;
        m_Xml := m_Loan_Str || m_Skinstvalue || '</root>';
      ELSE
        m_Xml := '';
      END IF;
    END IF;
    p_Out_Xml := m_Xml;
    p_Ret_Msg := 'T';
  EXCEPTION
    WHEN OTHERS THEN
      p_Ret_Msg := 'T';
      p_Out_Xml := '';
      m_Retmsg  := 'Error Occured for file name:' || p_File_Name ||
                   ' and LAN:' || p_Loan_Account_No || ' SRNO:' || p_Srno ||
                   ' TENOR:' || p_Tenor || Substr(SQLERRM, 1, 2000);
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Resch_Varitions',
                                                    p_Errmsg   => m_Retmsg);
  END Prc_Lms_Bulk_Resch_Varitions;
  PROCEDURE Prc_Lms_Bulk_Dre_level1(p_Org_Code      IN VARCHAR2,
                                    p_File_Name     IN VARCHAR2,
                                    p_Business_Date IN DATE,
                                    p_Outstr        OUT VARCHAR2) IS
    TYPE Type_Dre IS TABLE OF t_Lms_Genbulk_Dre%ROWTYPE;
    Rec_Dre  Type_Dre := Type_Dre();
    m_Retstr VARCHAR2(4000);
    Err_Dre_Setup EXCEPTION;
    Err_Dre_Val EXCEPTION;
    Err_Level2_Insert EXCEPTION;
    TYPE Type_Col IS TABLE OF VARCHAR2(4000);
    m_Rec_Columns Type_Col := Type_Col();
    m_Colname     VARCHAR2(4000);
    m_Colname1    VARCHAR2(4000);
    m_Err2_Cnt    NUMBER := 0;
    m_cnt  NUMBER := 0;
  BEGIN
    Prc_Lms_Bulk_Setup_Val(p_Org_Code  => p_Org_Code,
                           p_Filename  => p_File_Name,
                           p_Tran_Type => 'DRE',
                           p_level=>'LEVEL1',
                           p_Retmsg    => m_Retstr);
    IF m_Retstr <> 'T' THEN
      RAISE Err_Dre_Setup;
    END IF;
    SELECT * BULK COLLECT

      INTO Rec_Dre
      FROM t_Lms_Genbulk_Dre t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Filename = p_File_Name
       AND t.Sz_Errmsg IS NULL
       AND t.Sz_Stage2_Err IS NULL;
           
    IF Rec_Dre.Count > 0 THEN
      FOR i IN Rec_Dre.First .. Rec_Dre.Last LOOP
        Prc_Lms_Bulk_Dre_Val(p_Org_Code          => p_Org_Code,
                             p_Srno              => Rec_Dre(i).Row_Srno,
                             p_Loan_Account_No   => Rec_Dre(i)
                                                    .Sz_Loan_Account_No,
                             p_Dre_Amount        => Rec_Dre(i).f_Dre_Amount,
                             p_Instrument_Type   => Upper(Rec_Dre(i)
                                                          .Sz_Instrument_Type),
                             p_Instrument_Loc    => Upper(Rec_Dre(i)
                                                          .Sz_Instrument_Loc),
                             p_Instrument_No     => Rec_Dre(i)
                                                    .i_Instrument_No,
                             p_Ifsc_Code         => Upper(Rec_Dre(i)
                                                          .Sz_Ifsc_Code),
                             p_Bank_Code         => Upper(Rec_Dre(i)
                                                          .Sz_Bank_Code),
                             p_Bank_Branch_Code  => Upper(Rec_Dre(i)
                                                          .Sz_Bank_Branch_Code),
                             p_Account_Type      => Upper(Rec_Dre(i)
                                                          .Sz_Account_Type),
                             p_Bank_Accountno    => Upper(Rec_Dre(i)
                                                          .Sz_Bank_Accountno),
                             p_Deposit_Bank_Code => Upper(Rec_Dre(i)
                                                          .Sz_Deposit_Bank_Code),
                             p_Instrument_Date   => Rec_Dre(i).Dt_Instrument,
                             p_Utr_Number        => Upper(Rec_Dre(i)
                                                          .Sz_Utr_Number),
                             p_Value_Date        => Rec_Dre(i).Dt_Value_Date,
                             p_File_Name         => p_File_Name,
                             p_Business_Date     => p_Business_Date,
                             p_Userid            => Rec_Dre(i).Sz_Userid,
                             P_LEVEL_FLAG        => 'LEVEL1',
                             p_card_type         => Rec_Dre(i).SZ_FIELD2, -- issue fixed : 149575(removed upper function)
                             p_CARD_HOLDER_NM    => Rec_Dre(i)
                                                    .SZ_CARD_HOLDER_NM,
                             P_DC_ISSUING_BANK   => Rec_Dre(i)
                                                    .SZ_DC_ISSUING_BANK,
                             P_CARD_EXP_DATE     => Rec_Dre(i).SZ_FIELD3,
                             P_MOB_NO            => Rec_Dre(i).SZ_FIELD4,
                             P_CARD_SUBTYPE      => Rec_Dre(i).SZ_CARD_TYPE,
                             P_UPI_VPA           => Rec_Dre(i).SZ_UPI_VPA,
                             P_DT_RECEIPT        => Rec_Dre(i).DT_RECEIPT,
                             P_DEPOSIT_REF_NO    => Rec_Dre(i)
                                                    .SZ_DEPOSIT_REF_NO,
                             P_PROC_LOC          => Rec_Dre(i).SZ_PROC_LOC, -- Added for IBT Enh.
                             p_Retmsg            => m_Retstr);
        IF m_Retstr <> 'T' THEN
          RAISE Err_Dre_Val;
        END IF;
      END LOOP;
    END IF;
    p_Outstr:='T';
  EXCEPTION
    WHEN Err_Dre_Val THEN
      p_Outstr := m_Retstr || '-LEVEL1 VALIDATION';
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_DRE_Val',
                                                    p_Errmsg   => m_Retstr);
    
    WHEN OTHERS THEN
      p_Outstr := m_Retstr || '-LEVEL1 VALIDATION';
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Dre_level1',
                                                    p_Errmsg   => m_Retstr);
    
  END Prc_Lms_Bulk_Dre_level1;
  
  PROCEDURE Prc_Dre_Screen_Validations(p_Org_Code          IN VARCHAR2,
                                 p_Srno              NUMBER,
                                 p_Loan_Account_No   IN VARCHAR2,
                                       p_Dre_Amount        IN VARCHAR2, -- issue fix 149646
                                 p_Instrument_Type   IN VARCHAR2,
                                 p_Instrument_Loc    IN VARCHAR2 DEFAULT NULL,
                                 p_Instrument_No     IN VARCHAR2 DEFAULT NULL,
                                 p_Ifsc_Code         IN VARCHAR2 DEFAULT NULL,
                                 p_Bank_Code         IN VARCHAR2 DEFAULT NULL,
                                 p_Bank_Branch_Code  IN VARCHAR2 DEFAULT NULL,
                                 p_Account_Type      IN VARCHAR2 DEFAULT NULL,
                                 p_Bank_Accountno    IN VARCHAR2 DEFAULT NULL,
                                 p_Deposit_Bank_Code IN VARCHAR2 DEFAULT NULL,
                                 p_Instrument_Date   IN DATE DEFAULT NULL,
                                 p_Utr_Number        IN VARCHAR2 DEFAULT NULL,
                                 p_Value_Date        IN DATE DEFAULT NULL,
                                 p_File_Name         IN VARCHAR2,
                                 p_Business_Date     IN DATE,
                                 p_Userid            IN VARCHAR2,
                                 P_LEVEL_FLAG        IN VARCHAR2 DEFAULT NULL,
                                       p_card_type         IN VARCHAR2 DEFAULT NULL,
                                       p_CARD_HOLDER_NM    IN VARCHAR2 DEFAULT NULL,
                                       P_DC_ISSUING_BANK   IN VARCHAR2 DEFAULT NULL,
                                       P_CARD_EXP_DATE     IN VARCHAR2 DEFAULT NULL,
                                       P_MOB_NO            IN VARCHAR2 DEFAULT NULL,
                                       P_CARD_SUBTYPE      IN VARCHAR2 DEFAULT NULL,
                                       P_DEPOSIT_REF_NO    IN VARCHAR2 DEFAULT NULL, -- Issue Fix : 149372
                                       P_DT_RECEIPT        IN DATE, -- Issue Fix : 149367
                                       P_UPI_VPA           IN VARCHAR2 DEFAULT NULL, --issue fix : 149646 on 9th Mar 2017
                                       P_PROC_LOC          IN VARCHAR2 DEFAULT NULL, -- Added for IBT Enh.
                                 p_Retmsg            OUT VARCHAR2) IS
    m_Retmsg            VARCHAR2(4000);
    m_Err_Msg           VARCHAR2(4000);
    m_Module            VARCHAR2(10);
    m_Preturn           VARCHAR2(4000);
    m_Datediff          NUMBER;
    m_Rangedt           DATE;
    m_Disbflag          CHAR(1) := 'Y';
    m_Account_Status    t_Lms_Loan_Account.c_Account_Status%TYPE;
    m_Additional_Status t_Lms_Loan_Account.c_Additional_Status%TYPE;
    m_Cnt               NUMBER := 0;
    m_Asstcnt           NUMBER := 0;
    m_Customer_No       t_Lms_Loan_Account.Sz_Customer_No%TYPE;
    m_Tran_Head         VARCHAR2(4000);
    m_Apor_Amt          VARCHAR2(4000); --NUMBER := 0;
    m_Tran_Id           VARCHAR2(1000);
    m_Receipt_No        NUMBER := 0;
    m_Inst_Coll         VARCHAR2(1000);
    m_Inst_Pay_Op       VARCHAR2(1000);
    m_Tds_Amt           VARCHAR2(1000);
    m_Man_Apportion     VARCHAR2(1000);
    m_Return_Msg        VARCHAR2(4000);
    m_Loan_Account_No   t_Lms_Loan_Account.Sz_Loan_Account_No%TYPE;
    m_Micr_Code         v_Mst_Bank_Branch.Szmicrcode%TYPE;
    m_Dre_Amount        VARCHAR2(4000);
    m_Reterr            VARCHAR2(4000);
    Err_Ext_Dre_Val EXCEPTION;
    --m_Value_Date      DATE;
    m_Vdt_Flag        CHAR(1) := 'N';
    m_Bank_Code       Cmn_Vew_Bankbranch_Master.Sz_Bank_Code%TYPE;
    m_Bankbranch_Code Cmn_Vew_Bankbranch_Master.Sz_Bankbranch_Code%TYPE;
    m_Instrument_Date DATE := Trunc(p_Instrument_Date);
    m_Utr_Cnt         NUMBER := 0;
    m_Utr_Cnt1        NUMBER := 0;
    m_lan_count       number := 0;
    m_Dup_Count       NUMBER := 0;
    m_err_dup_msg  VARCHAR2(4000);
    m_dt              VARCHAR2(10); -- Issue Fix : 150310
  BEGIN
   
    select count(1)
      into m_lan_count
      from t_Lms_Loan_Account t
     where t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Loan_Account_No = p_Loan_Account_No;
  
    if m_lan_count = 0 AND P_LEVEL_FLAG = 'LEVEL1' then
      UPDATE t_Lms_Genbulk_Dre t
         SET Sz_Errmsg = Sz_Errmsg || 'Invalid Loan Account Number'
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Sz_Filename = p_File_Name
         AND t.Row_Srno = p_Srno;
      return;
    end if;
  
    --INSTRUMENT AMOUNT SAME AS DRE AMOUNT
    SELECT t.c_Account_Status,
           t.c_Additional_Status,
           t.Sz_Customer_No,
           t.Sz_Org_Branch_Code
      INTO m_Account_Status,
           m_Additional_Status,
           m_Customer_No,
           m_Inst_Coll
      FROM t_Lms_Loan_Account t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Loan_Account_No = p_Loan_Account_No;
    IF Trunc(p_Value_Date) > Trunc(p_Business_Date) THEN
      m_Err_Msg := '###ERROR:Value date should be less than or equal to business date';
      m_Retmsg:=m_Err_Msg;
    END IF;
    if m_Retmsg is null then
    IF Trunc(p_Value_Date) < Trunc(p_Business_Date) THEN
      m_Vdt_Flag := 'Y';
    ELSE
      m_Vdt_Flag := 'N';
    END IF;
	 IF m_Vdt_Flag='Y' THEN
      IF m_Additional_Status IS NOT NULL THEN
        IF m_Additional_Status ='RD' THEN
          m_Err_Msg := '###ERROR:Backdate DRE can not be done as account is pending for Restructure';
          m_Retmsg:=m_Err_Msg;       
        END IF;   
      END IF;  
    END IF;
    UPDATE t_Lms_Genbulk_Dre d
       SET d.c_Vdt_Flag = m_Vdt_Flag
     WHERE d.Sz_Org_Code = p_Org_Code
       AND d.Row_Srno = p_Srno
       AND d.Sz_Loan_Account_No = p_Loan_Account_No
       AND d.Sz_Filename = p_File_Name;
    --COMMON FOR DRE AND BACK DATED DRE
    /*  IF p_Vdt_Flag = 'Y' AND p_Value_Date IS NOT NULL THEN
      m_Module := 'BD';
    ELSE
      m_Module := 'DRE';
    END IF;*/
    m_Module := 'DRE';
    IF m_Account_Status <> 'L' THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'ACCOUNT_STATUS',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    END IF;
      --IF p_Instrument_Type IN ('CH', 'PO', 'DD', 'IM', 'NT', 'RT') THEN -- Commented for Additional Payment Modes Enhancement
      IF p_Instrument_Type IN ('CH', 'PO', 'DD', 'IM', 'NT', 'RT', 'DC') THEN
        -- Added for Additional Payment Modes Enhancement


      IF p_Instrument_Loc IS NULL AND
         p_Instrument_Type IN ('CH', 'PO', 'DD') THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'INSTLOC',
                                             p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue Fix : 149662
      END IF;
      IF p_Instrument_No IS NULL AND
         p_Instrument_Type IN ('CH', 'PO', 'DD') THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'INSTNO',
                                             p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue Fix : 149662
      END IF;
      IF p_Account_Type IS NULL AND p_Instrument_Type = 'CH' THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'ACT',
                                             p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue Fix : 149662
      END IF;
      IF p_Bank_Accountno IS NULL AND p_Instrument_Type = 'CH' THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'ACNO',
                                             p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue Fix : 149662
      END IF;
        IF (p_Ifsc_Code IS NULL AND
           p_Instrument_Type IN ('CH', 'PO', 'DD', 'IM', 'NT', 'RT')) THEN
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'IFSC',
                                             p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue Fix : 149662
      END IF;
      /*IF p_Ifsc_Code IS NULL THEN
        IF p_Bank_Code IS NULL AND
           p_Instrument_Type IN ('CH', 'PO', 'DD', 'IM', 'NT', 'RT') THEN
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'BANK',
                                               p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || p_Instrument_Type;
        END IF;
        IF p_Bank_Branch_Code IS NULL AND
           p_Instrument_Type IN ('CH', 'PO', 'DD', 'IM', 'NT', 'RT') THEN
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'BRANCH',
                                               p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || p_Instrument_Type;
        END IF;
      END IF;*/
        IF p_Deposit_Bank_Code IS NULL AND
           p_Instrument_Type IN ('CH', 'IM', 'NT', 'RT') THEN


          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'DEPOSIT',
                                             p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue Fix : 149662
      END IF;
      IF m_Instrument_Date IS NULL AND
           --p_Instrument_Type IN ('CH', 'PO', 'DD', 'IM', 'NT', 'RT') THEN -- Commented for Additional Payment Modes Enhancement
           p_Instrument_Type IN
           ('CH', 'PO', 'DD', 'IM', 'NT', 'RT', 'DC') THEN
          -- Added for Additional Payment Modes Enhancement

        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'DPI',
                                             p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue Fix : 149662
      END IF;
        IF p_Utr_Number IS NULL AND p_Instrument_Type IN ('IM', 'NT', 'RT') THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'UTR',
                                             p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue Fix : 149662
      END IF;
    ELSIF /*m_Instrument_Date IS NULL AND*/
     p_Instrument_Type = 'CA' THEN
      m_Instrument_Date := Trunc(Fun_Getbusinessdate(p_Org_Code));
    END IF;
  
      IF p_Bank_Accountno IS not null AND length(p_Bank_Accountno) > 20 AND
         p_Instrument_Type IN ('CH', 'IM', 'NT', 'RT', 'UP') THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'BANK_ACCT_LEN',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg; --issue fix : 149685 on 9th Mar 2017
      END IF;
      /* Start - Issue Fix : 149372 */
      If P_DEPOSIT_REF_NO is not null and length(P_DEPOSIT_REF_NO) > 15 Then
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'DEP_REF_NO_LEN',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      End If;
      /* End - Issue Fix : 149372 */
    
      /* Start - Issue Fix : 149367 */
      If P_DT_RECEIPT is null Then
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'RECEIPT_DT_MAND',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      Elsif P_DT_RECEIPT >
            pkg_general_services.get_business_date(p_Org_Code) Then
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'INVALID_RECEIPT_DT',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      End If;
      /* End - Issue Fix : 149367 */
      ------------START newly added on 22nd feb 2017 for new instrument type validation UP, MW, DC
    
      ---transaction_id is mandatory for p_Instrument_Type --  'UP', 'MW' -22-feb-2017
    
      IF p_Utr_Number IS NULL AND p_Instrument_Type IN ('UP', 'MW') THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'TRAN_id',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
      END IF;
    
      ---card no is mandatory for p_Instrument_Type --  'DC'
    
      IF p_Utr_Number IS NULL AND p_Instrument_Type IN ('DC') THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'CARD_NO',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
      END IF;
    
      IF p_Utr_Number IS NOT NULL AND p_Instrument_Type IN ('UP', 'MW') AND
         LENGTH(p_Utr_Number) > 20 THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'TRAN_ID_LEN',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
      END IF;
    
      IF p_Instrument_Type = 'UP' AND P_UPI_VPA IS NOT NULL AND
         LENGTH(P_UPI_VPA) > 100 THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'UPI_VPA_LEN',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF; --issue fix : 149646 on 9th Mar 2017                                       
      If p_Instrument_Type = 'MW' AND
         (CASE WHEN
          TRIM(TRANSLATE(P_MOB_NO, '0123456789', '          ')) IS NULL THEN 0 ELSE 1 END) <> 0 then
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'INVALID_MOB_NO',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
      End If;
      IF p_Dc_Issuing_Bank IS NOT NULL AND Length(p_Dc_Issuing_Bank) > 100 THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'ISSUING_BANK_LEN',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF; --- issue fix : 149646 on 9th Mar 2017 --Issue fix : 150310 on 15th Mar
    
      IF length(p_Mob_No) > 12 THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'MOB_NO_LEN',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 150310
      END IF;
    
      IF p_Instrument_Type in ('DC', 'UP') AND
         length(p_Card_Holder_Nm) > 100 THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'CARD_HOLDER_LEN',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 150310
      END IF;
    
      IF p_Instrument_Type = 'DC' then
      
        IF p_card_type is NULL THEN
          -- if card type is null
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'CARD_TYPE',
                                               p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
        
        ELSIF p_card_type IS NOT NULL and p_card_type not in ('DC', 'CC') THEN
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'INVALID_CARD_TYPE',
                                               p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
        END IF;
      
        If P_CARD_SUBTYPE is not null and
           P_CARD_SUBTYPE not in ('VC', 'RP', 'MC', 'AM', 'VE', 'ME', 'OT') Then
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'INVALID_CARD_SUBTYPE',
                                               p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
        End If;
        IF p_CARD_HOLDER_NM is NULL THEN
          -- if Card Holder is null
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'CARD_HOLDER',
                                               p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
        END IF;
      
        ---Date of payment mandatory is already handled for p_Instrument_Type 'DC'
      
        ---Card No. mandatory is already handled for p_Instrument_Type 'DC'
      
        IF p_Utr_Number IS NOT NULL AND length(p_Utr_Number) <> 16 THEN
          -- if Card No.should be of 16 digits
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'CARD_NO_LEN',
                                               p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
        END IF;
      
        IF p_Utr_Number IS NOT NULL AND
           (CASE WHEN
            TRIM(TRANSLATE(p_Utr_Number, '0123456789', '          ')) IS NULL THEN 0 ELSE 1 END) <> 0 then
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'INVALID_CARD_NO',
                                               p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
        END IF;
      
        IF P_DC_ISSUING_BANK IS NULL THEN
          --Issueing Bank/Institution - Mandatory
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'ISSUING_BANK',
                                               p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
        END IF;
      
        IF P_CARD_EXP_DATE IS NULL THEN
          --CARD EXP DATE- Mandatory
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'CARD_EXP_DATE',
                                               p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
          /* Added for Issue fix : 150310 */
        ELSIF p_Card_Exp_Date is not null Then
          Begin
            --m_dt := To_Char(To_Date(p_Card_Exp_Date, 'MON-RR'), 'MM/RRRR');
            m_dt := To_Char(To_Date(p_Card_Exp_Date, 'MM/RRRR'), 'MM/RRRR');
          Exception
            when others then
              m_dt := -1;
          End;
        
          If m_dt = TO_CHAR(-1) OR instr(p_Card_Exp_Date, '/', 1) = 0 or
             length(substr(p_Card_Exp_Date,
                           instr(p_Card_Exp_Date, '/', 1) + 1)) <> 4 Then
            m_Err_Msg := '###ERROR:Card Expiry Date should be proper(Expected format : MM/YYYY)/Card Expiry Month should be between 1 to 12';
             m_Retmsg  := m_Retmsg || m_Err_Msg;
          End If;
        
          IF m_dt <> TO_CHAR(-1) and instr(p_Card_Exp_Date, '/', 1) <> 0 and length(substr(p_Card_Exp_Date,

                           instr(p_Card_Exp_Date, '/', 1) + 1)) = 4 Then
            /* End for Issue fix : 150310 */
            /*IF p_Card_Exp_Date IS NOT NULL AND
               To_Char(To_Date(p_Card_Exp_Date, 'MM/RRRR'), 'MM') NOT BETWEEN 1 AND 12 THEN
            
              m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                   p_Tran_Type => m_Module,
                                                   p_Err_Code  => 'CARD_EXP_MONTH_VAL',
                                                   p_File_Name => p_File_Name);
              m_Retmsg  := m_Retmsg || m_Err_Msg; --issue fix : 149672 on 9th Mar 2017
            End If;*/
/*            IF p_Card_Exp_Date IS NOT NULL AND
               To_Char(To_Date(p_Card_Exp_Date, 'MM/RRRR'), 'RRRR') NOT BETWEEN 2000 AND 3000 THEN
              m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                   p_Tran_Type => m_Module,
                                                   p_Err_Code  => 'CARD_EXP_YEAR_VAL',
                                                   p_File_Name => p_File_Name);
              m_Retmsg  := m_Retmsg || m_Err_Msg; --issue fix : 149672 on 9th Mar 2017
            End If;*/
            IF /*p_Card_Exp_Date IS NOT NULL AND*/ -- --CARD EXP DATE less than business date
             To_Date(p_Card_Exp_Date, 'MM/RRRR') <
             To_Date(To_Char(Pkg_General_Services.Get_Business_Date(p_Org_Code),
                             'MM/RRRR'),
                     'MM/RRRR') THEN

              /*m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'CARD_EXP_DATE_VAL',
              p_File_Name => p_File_Name);*/
              m_Err_Msg := '###ERROR:Card Expiry Month/Year should be greater than or equal to business Month/Year';
          m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue fix : 149356
        END IF;
      
      END IF;
        END IF;
      END IF;
      /* End for Issue fix : 150310 */
      ------------END newly added on 22nd feb 2017 for new instrument type validation UP, MW, DC
    ----newly added 
      IF p_Instrument_Type IN ('CA', 'IM', 'NT', 'RT') AND
       p_Instrument_Loc IS NOT NULL THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'CA1',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || p_Instrument_Type;
    END IF;
      IF p_Instrument_Type IN ('CA', 'IM', 'NT', 'RT') AND
       p_Instrument_No IS NOT NULL THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'CA2',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || p_Instrument_Type;
    END IF;
    IF p_Instrument_Type = 'CA' AND p_Ifsc_Code IS NOT NULL THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'CA3',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || '-CA';
    END IF;
    IF p_Instrument_Type = 'CA' AND p_Bank_Code IS NOT NULL THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'CA4',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || '-CA';
    END IF;
    IF p_Instrument_Type = 'CA' AND p_Bank_Branch_Code IS NOT NULL THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'CA5',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || '-CA';
    END IF;
    IF p_Instrument_Type <> 'CH' AND p_Account_Type IS NOT NULL THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'CA6',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || p_Instrument_Type;
    END IF;
    IF p_Instrument_Type IN ('PO', 'DD', 'CA') AND
       p_Bank_Accountno IS NOT NULL THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'CA7',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || p_Instrument_Type;
    END IF;
    IF p_Instrument_Type IN ('PO', 'DD', 'CA') AND
       p_Deposit_Bank_Code IS NOT NULL THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'CA8',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || p_Instrument_Type;
    END IF;
    IF p_Instrument_Type = 'CA' AND p_Instrument_Date IS NOT NULL THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'CA9',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || '-CA';
    END IF;
    IF p_Instrument_Type IN ('CH', 'CA', 'PO', 'DD') AND
       p_Utr_Number IS NOT NULL THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'UTR11',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || p_Instrument_Type;
    END IF;
    --
      --- issue fix : 149646 on 9th mar 2017
      Begin
        select count(1)
          into m_cnt
          from dual
         where to_number(p_Dre_Amount) = p_Dre_Amount;
      Exception
        when others then
          m_cnt := -1;
      End;
    
      IF p_Dre_Amount is not null and m_cnt = -1
      --TRIM(TRANSLATE(p_Dre_Amount, '0123456789.', '           ')) IS not NULL 
       then
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'DREAMOUNT_VAL',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF; --- issue fix : 149646 on 9th mar 2017
      
      If m_cnt <> -1 Then
      IF Nvl(to_number(p_Dre_Amount), 0) <= 0 THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'DREAMOUNT',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg; -- Issue Fix : 149662
      END IF;
        IF instr(to_number(p_Dre_Amount), '.', 1) = 0 and
           length(to_number(p_Dre_Amount)) > 18 THEN
          m_Err_Msg := '###ERROR:Length of Dre amount cannot be more than 18 digits';
          m_Retmsg  := m_Retmsg || m_Err_Msg;
      End If;
        IF instr(to_number(p_Dre_Amount), '.', 1) <> 0 and
           length(substr(to_number(p_Dre_Amount),
                         1,
                         instr(to_number(p_Dre_Amount), '.', 1) - 1)) > 18 THEN
          m_Err_Msg := '###ERROR:Length of Dre amount before decimal cannot be more than 18 digits';
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        END IF;
        IF instr(to_number(p_Dre_Amount), '.', 1) <> 0 and
           length(substr(to_number(p_Dre_Amount),
                         instr(to_number(p_Dre_Amount), '.', 1) + 1)) > 2 THEN
          m_Err_Msg := '###ERROR:Length of Dre amount after decimal cannot be more than 2 digits';
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        END IF;
      End If;
    IF m_Additional_Status = 'PP' THEN
      IF m_Vdt_Flag='Y' THEN ---ISSUE FIXED 144871


        m_Err_Msg:='###ERROR:Pending request exist for Part Prepayment can not make a new Back Dated DRE request';
      ELSE
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'ADD_STATUS_PP',
                                           p_File_Name => p_File_Name);
      END IF;
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF m_Additional_Status = 'PF' THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'ADD_STATUS_PF',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF m_Additional_Status IN ('PF', 'PS') THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'ADD_STATUS_PS',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    END IF;
    --------qUERY
    SELECT ((SELECT Pkg_General_Services.Get_Back_Inst_Date(p_Org_Code,
                                                            p_Business_Date) Rang
               FROM Dual) - m_Instrument_Date) Dtdiff,
           trunc(Pkg_General_Services.Get_Back_Inst_Date(p_Org_Code,
                                                         p_Business_Date)) Rangdt
      INTO m_Datediff, m_Rangedt
      FROM Dual;
    IF m_Instrument_Date IS NOT NULL THEN
      SELECT CASE
               WHEN MIN(p.Dt_Disbursement) - m_Instrument_Date <= 0 THEN
                'Y'
               ELSE
                'N'
             END Dtdiff1
        INTO m_Disbflag
        FROM t_Lms_Disb_Dtls p
       WHERE p.Sz_Org_Code = p_Org_Code
         AND p.Sz_Loan_Account_No = p_Loan_Account_No;
    END IF;
      IF p_Utr_Number IS NOT NULL AND
         p_Instrument_Type IN ('IM', 'NT', 'RT') THEN
      SELECT COUNT(1)
        INTO m_Utr_Cnt
        FROM t_Lms_Instruments i
       WHERE i.Sz_Org_Code = p_Org_Code
         AND i.Sz_Utr_Number = p_Utr_Number;
      /* SELECT COUNT(1)
       INTO m_Utr_Cnt1
       FROM t_Lms_Genbulk_Dre d
      WHERE d.Sz_Org_Code = p_Org_Code
        AND d.Sz_Filename <> p_File_Name
        AND d.Sz_Utr_Number = p_Utr_Number
        and d.sz_stage2_err is null;*/
    END IF;
    ------------
    IF (m_Rangedt - m_Instrument_Date) > 0 THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => 'DRE',
                                           p_Err_Code  => 'RANGE',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || ':' || m_Rangedt ||
                   '(BACK SUPPLIMENT DATE)';
    
    elsIF m_Datediff > 0  THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => 'DRE',
                                           p_Err_Code  => 'RANGED',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || p_Business_Date;
    END IF;
    IF m_Utr_Cnt > 0 /*OR m_Utr_Cnt1 > 0*/
     THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => 'DRE',
                                           p_Err_Code  => 'DUPUTR',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    END IF;
   /* IF m_Datediff > 0  THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => 'DRE',
                                           p_Err_Code  => 'RANGED',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || p_Business_Date;
    END IF;*/
    IF m_Instrument_Date > p_Business_Date THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'INSTDATE',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    END IF;
    IF m_Disbflag = 'N' THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'DISBDATE',
                                           p_File_Name => p_File_Name);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    END IF;
      ----ADDED ON DATE 31-JAN-2017 issue 144270
   /*   begin
      SELECT DISTINCT Cnt
        INTO m_Dup_Count
        FROM t_Instrument_Details t,
             (SELECT COUNT(k.i_Instrument_No) Cnt,
                     k.i_Instrument_No,
                     k.Sz_Ifsc_Code,
                     k.Sz_Bank_Code,
                     k.Sz_Bank_Branch_Code
                FROM t_Lms_Genbulk_Dre k
               WHERE k.Sz_Instrument_Type IN ('CH', 'PO', 'DD')
               GROUP BY k.i_Instrument_No,
                        k.Sz_Ifsc_Code,
                        k.Sz_Bank_Code,
                        k.Sz_Bank_Branch_Code
              HAVING COUNT(k.i_Instrument_No) > 1) k
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Instrument_No = k.i_Instrument_No
         AND t.Sz_Status <> 'BOU'
         AND t.Sz_Bank_Code = k.Sz_Bank_Code
         AND t.Sz_Branch_Code = k.Sz_Bank_Branch_Code
         AND Rownum <= 1;
      exception
        when others then
          m_Dup_Count:=0;
      end;
      if m_Dup_Count = 0 then
        begin
          select count(d.i_Instrument_No)
          into m_Dup_Count
            from (SELECT k.sz_filename,
                         count(k.i_Instrument_No) i_Instrument_No,
                         k.Sz_Ifsc_Code,
                         k.Sz_Bank_Code,
                         k.Sz_Bank_Branch_Code
                    FROM t_Lms_Genbulk_Dre k
                   WHERE k.Sz_Instrument_Type IN ('CH', 'PO', 'DD')
                  --and k.i_instrument_no='555444'
                  --and sz_filename ='DRE_BULK_SYSADMINX_31012017_1686_i.xls'
                   GROUP BY k.i_Instrument_No,
                            k.Sz_Ifsc_Code,
                            k.Sz_Bank_Code,
                            k.Sz_Bank_Branch_Code,
                            k.sz_filename
                  HAVING COUNT(k.i_Instrument_No) > 1) d;
        EXCEPTION
          WHEN OTHERS THEN
            m_Dup_Count := 0;
        END;
      end if;
      IF m_Dup_Count > 1 THEN
        m_err_dup_msg:= 'Duplicate Instrument found for Same IFSC,Bank and Branch';
       
        UPDATE t_Lms_Genbulk_Dre t
         SET Sz_Errmsg = Sz_Errmsg || m_err_dup_msg
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Sz_Filename = p_File_Name
         AND t.Row_Srno = p_Srno
         and t.Sz_Ifsc_Code is not null
         and t.Sz_Bank_Code is not null
         and t.Sz_Bank_Branch_Code is not null;
      END IF;*/
      ---END
    --This validation for perticular back dated dre
    IF m_Vdt_Flag = 'Y' THEN
      IF p_Value_Date IS NULL THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => 'BD',
                                             p_Err_Code  => 'VALDATE',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
    END IF;
    IF m_Vdt_Flag = 'Y' THEN
      IF p_Value_Date > p_Business_Date THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => 'BD',
                                             p_Err_Code  => 'VALDATE1',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
      SELECT COUNT(DISTINCT t.Sz_Currency_Code) Cnt
        INTO m_Cnt
        FROM t_Lms_Loan_Account t, t_Lms_Loan_References Lr
       WHERE t.Sz_Org_Code = Lr.Sz_Org_Code
         AND t.Sz_Loan_Account_No = Lr.Sz_Loan_Account_No
         AND Lr.Sz_Customer_No = p_Loan_Account_No
         AND Lr.Sz_Org_Code = p_Org_Code;
      IF m_Cnt > 1 THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => 'BD',
                                             p_Err_Code  => 'CURR',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
      SELECT COUNT(t.Sz_Loan_Account_No) Cval
        INTO m_Asstcnt
        FROM t_Lms_Loan_Account t
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.c_Account_Status = 'L'
         AND Nvl(t.c_Additional_Status, 'N') = 'R';
      IF m_Asstcnt > 0 THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => 'BD',
                                             p_Err_Code  => 'ASTCNT',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
      m_Err_Msg := Fun_Lms_Validate_Valuedate_Vdt(p_Org_Code        => p_Org_Code,
                                                  p_Loan_Account_No => p_Loan_Account_No,
                                                  p_Inputvalue_Date => p_Value_Date);
      IF m_Err_Msg IS NOT NULL THEN
        m_Retmsg := m_Retmsg || '###ERROR:' || m_Err_Msg;
      END IF;
      Prc_Lms_Pending_Trans_Val(p_Org_Code        => p_Org_Code,
                                p_Loan_Account_No => p_Loan_Account_No,
                                p_Module          => 'DRE',
                                p_Return_Msg      => m_Preturn);
      IF (m_Preturn = m_Module || '|LMSCMN0002') THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'PENDING1',
                                             p_File_Name => p_File_Name);
          m_Retmsg  := m_Retmsg ||
                       REPLACE(m_Err_Msg, 'DRE', 'Backdated DRE');
      END IF;
    END IF;
    -----PROCEDURE VALIDATIONS
    IF m_Vdt_Flag = 'N' THEN
      Prc_Lms_Pending_Trans_Val(p_Org_Code        => p_Org_Code,
                                p_Loan_Account_No => p_Loan_Account_No,
                                p_Module          => 'DRE',
                                p_Return_Msg      => m_Preturn);
      IF (m_Preturn = m_Module || '|LMSCMN0001') THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'PENDING',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
      IF (m_Preturn = m_Module || '|LMSCMN0002') THEN
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'PENDING1',
                                             p_File_Name => p_File_Name);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
    END IF;
    end if;
    IF P_LEVEL_FLAG = 'LEVEL1' THEN
      UPDATE t_Lms_Genbulk_Dre t
         SET Sz_Errmsg = Sz_Errmsg || m_Retmsg
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Sz_Filename = p_File_Name
         AND t.Row_Srno = p_Srno;
    ELSE
       UPDATE t_Lms_Genbulk_Dre t
         SET T.SZ_STAGE2_ERR = T.SZ_STAGE2_ERR || m_Retmsg
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Sz_Filename = p_File_Name
         AND t.Row_Srno = p_Srno;
    END IF;
    IF m_Retmsg IS NULL THEN
       p_Retmsg:='T';
    ELSE
        p_Retmsg:=m_Retmsg;
    END IF;
EXCEPTION
  WHEN OTHERS THEN
    p_Retmsg:='-101';   
end Prc_Dre_Screen_Validations;
  PROCEDURE Prc_Lms_Bulk_Resch_Level1(p_Org_Code IN VARCHAR2,
                                      p_File_Name     IN VARCHAR2,
                                      p_Business_Date IN DATE,
                                      p_Outstr        OUT VARCHAR2) IS
    TYPE Type_Resch IS TABLE OF t_Lms_Genbulk_Reschedule%ROWTYPE;
    Rec_Resch Type_Resch := Type_Resch();
    m_Retstr  VARCHAR2(4000);
    Err_Resch_Setup EXCEPTION;
    Err_Resch_Val EXCEPTION;
    Err_Level2_Insert EXCEPTION;
    TYPE Type_Col IS TABLE OF VARCHAR2(4000);
    m_Rec_Columns   Type_Col := Type_Col();
    m_Colname       VARCHAR2(4000);
    m_Colname1      VARCHAR2(4000);
    m_Err2_Cnt      NUMBER := 0;
    m_Change_Factor VARCHAR2(50);
    m_Xml           VARCHAR2(4000);
    M_LN_CNT NUMBER := 0;
    m_Tr_Cnt        NUMBER := 0;
  BEGIN
     ---ISSUE FIXED 147494
      SELECT COUNT(1)
      INTO M_LN_CNT
   FROM
   (
   SELECT DISTINCT T.Sz_Loan_Account_No
              FROM t_Lms_Genbulk_Reschedule t, T_LMS_LOAN_ACCOUNT P
             WHERE t.Sz_Org_Code = P.SZ_ORG_CODE
               AND t.Sz_Loan_Account_No = P.Sz_Loan_Account_No
               AND T.SZ_ORG_CODE = p_Org_Code
               AND t.Sz_Filename = p_File_Name);
    IF  M_LN_CNT=0 THEN
    UPDATE t_Lms_Genbulk_Reschedule t
       SET t.Sz_Errmsg = Sz_Errmsg || '###ERROR:Invalid Loan Account Number'


     WHERE Sz_Loan_Account_No IN
           (SELECT DISTINCT T.Sz_Loan_Account_No
              FROM t_Lms_Genbulk_Reschedule t, T_LMS_LOAN_ACCOUNT P
             WHERE t.Sz_Org_Code = P.SZ_ORG_CODE
               AND t.Sz_Loan_Account_No <> P.Sz_Loan_Account_No
               AND T.SZ_ORG_CODE = p_Org_Code
               AND t.Sz_Filename = p_File_Name)
       AND T.SZ_ORG_CODE = p_Org_Code
       AND t.Sz_Filename = p_File_Name;
      return;
    end if;
    ---issue fixed 149797 for multitranche
    SELECT COUNT(1)
      INTO m_Tr_Cnt
      FROM (SELECT DISTINCT t.Sz_Loan_Account_No
              FROM t_Lms_Genbulk_Reschedule t, t_Lms_Tranche_Dtls p
             WHERE t.Sz_Org_Code = p.Sz_Org_Code
               AND t.Sz_Loan_Account_No = p.Sz_Loan_Account_No
               AND t.i_Tranche_No = p.i_Tranche_No
               AND t.Sz_Org_Code = '001'
               AND t.Sz_Filename = p_File_Name);
    IF m_Tr_Cnt = 0 THEN
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Errmsg = Sz_Errmsg || '###ERROR:Invalid Tranche Number'
       WHERE Sz_Loan_Account_No IN
             (SELECT DISTINCT t.Sz_Loan_Account_No
                FROM t_Lms_Genbulk_Reschedule t, t_Lms_Tranche_Dtls p
               WHERE t.Sz_Org_Code = p.Sz_Org_Code
                 AND t.Sz_Loan_Account_No = p.Sz_Loan_Account_No
                 AND t.i_Tranche_No <> p.i_Tranche_No
                 AND t.Sz_Org_Code = p_Org_Code
                 AND t.Sz_Filename = p_File_Name)
         AND t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Filename = p_File_Name;
      RETURN;
    END IF;
    --
    Prc_Lms_Bulk_Setup_Val(p_Org_Code  => p_Org_Code,
                           p_Filename  => p_File_Name,
                           p_Tran_Type => 'RESCHEDULE',
                           P_LEVEL=>'LEVEL1',
                           p_Retmsg    => m_Retstr);
    IF m_Retstr <> 'T' THEN
      RAISE Err_Resch_Setup;
    END IF;
    SELECT * BULK COLLECT

      INTO Rec_Resch
      FROM t_Lms_Genbulk_Reschedule t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Filename = p_File_Name
       AND t.Sz_Errmsg IS NULL
       AND t.Sz_Stage2_Err IS NULL;
    IF Rec_Resch.Count > 0 THEN
      FOR i IN Rec_Resch.First .. Rec_Resch.Last LOOP
        SELECT Decode(Rec_Resch(i).c_Change_Factor,
                      'I',
                      'E',
                      Rec_Resch(i).c_Change_Factor) Fac
          INTO m_Change_Factor
          FROM Dual;
        Prc_Lms_Bulk_Resch_Val(p_Org_Code        => p_Org_Code,
                               p_Filename        => p_File_Name,
                               p_Loan_Account_No => Rec_Resch(i)
                                                    .Sz_Loan_Account_No,
                               p_Tranche_No      => Rec_Resch(i).i_Tranche_No,
                               p_Srno            => Rec_Resch(i).Row_Srno,
                               p_Repay_Freq      => Rec_Resch(i).c_Repay_Freq,
                               p_Change_Factor   => m_Change_Factor,
                               p_Cycleday        => Rec_Resch(i).i_Cycleday,
                               p_Installment_Amt => Rec_Resch(i)
                                                    .f_Installment_Amt,
                               p_Tenor           => Rec_Resch(i).i_Tenor,
                               p_Interestrate    => Rec_Resch(i)
                                                    .f_Interestrate,
                               p_Remarks         => Rec_Resch(i).Sz_Remarks,
                               p_Offset          => Rec_Resch(i)
                                                    .f_Offset_Rate,
                               p_Reason          => Rec_Resch(i).Sz_Reason,
                               p_Equated_Prin    => To_Number(Rec_Resch(i)
                                                              .c_Prin_Repay_Freq),
                               p_Business_Date   => p_Business_Date,
                               p_Userid          => Rec_Resch(i).Sz_Userid,
                               p_Level_Flag      => 'LEVEL1',
                               p_eff_inst_dt     => Rec_Resch(i)
                                                    .DT_EFFECTIVE_INST_DATE, -- Added for Reschedule on Partially Disbursed Cases
                               p_Retmsg          => m_Retstr);
        IF m_Retstr <> 'T' THEN
          RAISE Err_Resch_Val;
        END IF;
      END LOOP;
    END IF;
    p_Outstr := 'T';
  EXCEPTION
    WHEN Err_Resch_Val THEN
      p_Outstr := m_Retstr || '-LEVEL1 VALIDATION';
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Resch_Val',
                                                    p_Errmsg   => m_Retstr);
    WHEN OTHERS THEN
      p_Outstr := m_Retstr || '-LEVEL1 VALIDATION';
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_RESCH_level1',
                                                    p_Errmsg   => m_Retstr);
  END Prc_Lms_Bulk_Resch_Level1;
  PROCEDURE Prc_Resch_Screen_Validations(p_Org_Code        VARCHAR2,
                                         p_Filename        IN VARCHAR2,
                                         p_Loan_Account_No VARCHAR2,
                                         p_Tranche_No      VARCHAR2,
                                         p_Srno            NUMBER,
                                         p_Repay_Freq      NUMBER,
                                         p_Change_Factor   CHAR,
                                         p_Cycleday        NUMBER,
                                         p_Installment_Amt NUMBER,
                                         p_Tenor           NUMBER,
                                         p_Interestrate    NUMBER,
                                         p_Remarks         VARCHAR2,
                                         p_Offset          NUMBER,
                                         p_Reason          VARCHAR2,
                                         p_Equated_Prin    NUMBER,
                                         p_Business_Date   DATE,
                                         p_Userid          IN VARCHAR2 DEFAULT 'SYSADMIN',
                                         p_Level_Flag      IN VARCHAR2 DEFAULT NULL,
                                         p_eff_inst_dt     IN DATE, -- Added for Reschedule on Partially Disbursed Cases
                                         p_Retmsg          OUT VARCHAR2) IS
    m_Old_Repfreq  t_Lms_Loan_Account.c_Repay_Freq%TYPE;
    m_Accnt_Status t_Lms_Loan_Account.c_Account_Status%TYPE;
    m_Add_Sts      t_Lms_Loan_Account.c_Additional_Status%TYPE;
    m_Final_Disb   t_Lms_Loan_Account.c_Final_Disb_Yn%TYPE;
    m_Cycle_Day    t_Lms_Loan_Account.i_Cycleday%TYPE;
    m_Portfolio    t_Lms_Loan_Account.Sz_Portfolio_Code%TYPE;
    m_Retmsg       VARCHAR2(4000);
    Mf_Count       NUMBER := 0;
    m_Bal_Tenor    NUMBER := 0;
    m_New_Int_Rate t_Lms_Tranche_Sch_Param.f_Interestrate%TYPE;
    m_Balloon_Yn   CHAR(1);
    m_Flagretrage  CHAR(1);
    m_Total_Due    NUMBER := 0;
    --p_Return_Msg   VARCHAR2(4000);
    m_Tenor        VARCHAR2(4000); --NUMBER := 0;
    m_Emi          VARCHAR2(4000); --NUMBER := 0;
    m_Xml_Data     CLOB; --VARCHAR2(4000);
    m_Product_Code t_Lms_Product_Dtls.Sz_Product_Code%TYPE;
    m_Interestrate NUMBER := p_Interestrate;
    m_Proc_Retmsg  VARCHAR2(4000);
    Err_Emi_Tenor_Cal EXCEPTION;
    Err_Amortz_Param EXCEPTION;
    Err_Reschedule_Req EXCEPTION;
    m_Validyn          VARCHAR2(100);
    m_Errormsg         VARCHAR2(4000);
    m_Errorval         VARCHAR2(4000);
    m_Skipclob         CLOB;
    m_Stepclob         CLOB;
    m_Ballonclob       CLOB;
    m_Ademiclob        NUMBER := 0;
    m_Variations       VARCHAR2(4000);
    m_Ballonpay_Amount NUMBER := 0;
    m_Trantype         VARCHAR2(4000);
    m_Tranhead         VARCHAR2(4000);
    m_Osamt            VARCHAR2(4000); --NUMBER := 0;
    m_Taxamt           VARCHAR2(4000); --NUMBER := 0;
    m_Tranche_No       VARCHAR2(4000);
    m_Waive_Amount     VARCHAR2(4000);
    m_Due_Amount       VARCHAR2(4000);
    m_Cap_Amount       VARCHAR2(4000);
    --m_Tot_Amount        NUMBER := 0;
    m_Total_Amount      NUMBER := 0;
    m_Bpi_Recovery_Flag VARCHAR2(100);
    m_Bsrno             t_Lms_Balloon_Pay.i_Srno%TYPE;
    m_Bmonth            t_Lms_Balloon_Pay.i_Month_Ballon%TYPE;
    m_Bvalue            t_Lms_Balloon_Pay.f_Ballon_Pay%TYPE;
    m_Badj              t_Lms_Balloon_Pay.f_Ballon_Adj%TYPE;
    m_Min_Tenor         Prd_Mst_Product.Imintenor%TYPE; -- t_Lms_Product_Dtls.i_Min_Tenor%TYPE;
    m_Max_Tenor         Prd_Mst_Product.Imaxtenor%TYPE; --t_Lms_Product_Dtls.i_Max_Tenor%TYPE;
    m_Min_Inst_Amt      Prd_Mst_Product.Fmininstallment%TYPE; --t_Lms_Product_Dtls.f_Min_Inst_Amt%TYPE;
    m_Max_Inst_Amt      Prd_Mst_Product.Fmaxinstallment%TYPE; --t_Lms_Product_Dtls.f_Max_Inst_Amt%TYPE;
    m_Min_Int_Rate      Prd_Mst_Product.Ffloorrate%TYPE; --t_Lms_Product_Dtls.f_Min_Int_Rate%TYPE;
    m_Locking_Period    NUMBER := 0;
    m_Max_Intrate       Prd_Mst_Product.Fceilrate%TYPE; --Prd_Vew_Product.f_Pricing_Fix_Max_Int_Rate%TYPE;
    m_Min_Intrate       Prd_Vew_Product.f_Pricing_Fix_Min_Int_Rate%TYPE;
    --m_Inst_From NUMBER := 0;
    --m_Inst_To   NUMBER := 0;
    --m_Step_Adj  t_Lms_Step_Pay.Sz_Step_Adj%TYPE;
    --m_Step_Value    t_Lms_Step_Pay.f_Step_Value%TYPE;
    --m_Skip_Instfrom NUMBER := 0;
    --m_Skip_Instto   NUMBER := 0;
    m_Interest_Type t_Lms_Product_Dtls.c_Interest_Type%TYPE;
    m_Index_Code      Prd_Vew_Amort_Portfolio_Xref.Sz_Pricing_Idx_Rate_Code%TYPE;
    m_Index_Rate      Prd_Vew_Amort_Portfolio_Xref.Sz_Pricing_Idx_Rate_Code%TYPE;
    m_Spread_Code     Prd_Vew_Amort_Portfolio_Xref.Sz_Pricing_Idx_Spread_Code%TYPE;
    m_Idx_Spread_Rate Prd_Vew_Amort_Portfolio_Xref.f_Pricing_Idx_Spread_Rate%TYPE;
    m_Max_Offsetrate  Prd_Vew_Amort_Portfolio_Xref.f_Pricing_Idx_Max_Offset%TYPE;
    m_Reterr          VARCHAR2(4000);
    Err_Ext_Resh_Val EXCEPTION;
    m_Old_Interestrate t_Lms_Tranche_Dtls.f_Curr_Interestrate%TYPE;
    m_Old_Freq         t_Lms_Product_Dtls.i_Compounding_Freq%TYPE;
    m_Old_Cycle        t_Lms_Loan_Account.i_Cycleday%TYPE;
    --m_Osamt_Fee        v_Lms_Head_Wise_Due.Osamt%TYPE;
    --m_Event_Chg        NUMBER := 0;
    --m_Event_Tax        NUMBER := 0;
    --m_Return_Msg       VARCHAR2(4000);
    m_Fixed    NUMBER := 0;
    m_Variable NUMBER := 0;
    ----added by APRANSHU
    m_Instlmnt_To   NUMBER := 0;
    m_Next_Instlmnt NUMBER := 0;
    m_Excess_Amt    t_Lms_Loan_Account.f_Excess_Amt%TYPE;
    m_Value         m_Lms_Condition_Parameter.Sz_Value%TYPE;
    m_Change_Factor VARCHAR2(100);
    m_Module        VARCHAR2(4000) := 'RESCHEDULE';
    m_Err_Msg       VARCHAR2(4000);
    --m_Xml           VARCHAR2(4000);
    m_Equated_Prin t_Lms_Product_Dtls.f_Equated_Prin_Frq%TYPE;
    m_Prin_Freq    CHAR(1) := 'N';
    m_Dateofcycle  VARCHAR2(4000);
    m_Lan_Count    NUMBER := 0;
     M_BL_COUNT   NUMBER := 0;
     m_Variation_Flag t_Lms_Genbulk_Reschedule.c_Variation_Flag%TYPE;
    m_proc_err       VARCHAR(4000);
     m_Final_Disb_Yn t_Lms_Loan_Account.c_Final_Disb_Yn%TYPE;
    m_eff_inst_dt_cnt NUMBER := 0; -- Added for Reschedule on Partially Disbursed Cases
    M_DT_NEXT_INSTALLMENT t_lms_loan_account.DT_NEXT_INSTALLMENT%type;
    m_pre_emi_option      t_lms_loan_account.c_pre_emi_option%type; -- Added for bug : 151683
    m_CycleDay            NUMBER := 0; -- Month End as Due Date Enh.    
  BEGIN
    m_Retmsg := NULL;
    SELECT COUNT(1)
      INTO m_Lan_Count
      FROM t_Lms_Loan_Account t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Loan_Account_No = p_Loan_Account_No;
    IF m_Lan_Count = 0 AND p_Level_Flag = 'LEVEL1' THEN
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Errmsg = Sz_Errmsg || '###ERROR:Invalid Loan Account Number'


       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Sz_Filename = p_Filename
         AND t.Row_Srno = p_Srno;
      RETURN;
    END IF;
    BEGIN
      SELECT t.Sz_Product_Code, t.c_Interest_Type, t.i_Compounding_Freq
        INTO m_Product_Code, m_Interest_Type, m_Old_Freq
        FROM t_Lms_Product_Dtls t
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No;
    EXCEPTION
      WHEN OTHERS THEN
        m_Product_Code  := NULL;
        m_Interest_Type := 'F';
    END;
    BEGIN
      SELECT s.f_Curr_Interestrate
        INTO m_Old_Interestrate
        FROM t_Lms_Tranche_Dtls s
       WHERE s.Sz_Org_Code = p_Org_Code
         AND s.Sz_Loan_Account_No = p_Loan_Account_No;
    EXCEPTION
      WHEN OTHERS THEN
        m_Old_Interestrate := 0;
    END;
    BEGIN
      SELECT l.i_Cycleday
        INTO m_Old_Cycle
        FROM t_Lms_Loan_Account l
       WHERE l.Sz_Org_Code = p_Org_Code
         AND l.Sz_Loan_Account_No = p_Loan_Account_No;
    EXCEPTION
      WHEN OTHERS THEN
        m_Old_Cycle := 0;
    END;
    IF m_Old_Cycle <> Nvl(p_Cycleday, '33') OR
       m_Old_Interestrate <> m_Interestrate OR m_Old_Freq <> p_Repay_Freq THEN
      m_Bpi_Recovery_Flag := 'Y';
    ELSE
      m_Bpi_Recovery_Flag := 'N';
    END IF;
    /* Added for bug : 151683 */
    select a.c_pre_emi_option,a.c_final_disb_yn
      Into m_pre_emi_option,m_Final_Disb_Yn
      from t_lms_loan_account a
     where a.sz_org_code = p_Org_Code
       and a.sz_loan_account_no = p_Loan_Account_No;
     If m_Final_Disb_Yn = 'N' and m_pre_emi_option = 'Y' Then
      m_Err_Msg := '###ERROR:Pre-EMI cases cannot be rescheduled';
      m_Retmsg  := m_Retmsg || m_Err_Msg;       
     End If;    
    /* End for bug : 151683 */
    ---- added by APRANSHU to validate change factors ----------------------
    IF m_Interestrate = 0 AND p_Change_Factor NOT IN ('I','E') THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'INTRATE',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    END IF;
    -----------
    IF (p_Installment_Amt IS NULL AND p_Tenor IS NULL) AND
       p_Equated_Prin IS NULL THEN
      --m_Retmsg := 'At least one value from installment amount and tenure should be specified.';
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'P1',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF p_Installment_Amt IS NOT NULL AND p_Tenor IS NOT NULL THEN
      --m_Retmsg := 'Only one value from installment amount and tenure should be specified.';
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'P2',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF p_Change_Factor = 'T' AND p_Tenor IS NOT NULL THEN
      -- m_Retmsg := 'For change factor "TENURE", new tenure should not be specified.';
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'P3',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF p_Change_Factor = 'T' AND p_Installment_Amt IS NULL THEN
      --m_Retmsg := 'For change factor "TENURE", new installment amount should be specified.';
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'P4',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF p_Change_Factor = 'T' AND p_Installment_Amt = 0 THEN
      -- m_Retmsg := 'For change factor "TENURE", new installment amount should be greater than 0.';
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'P5',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF p_Change_Factor IN ('I','E') AND p_Installment_Amt IS NOT NULL THEN
      -- m_Retmsg := 'For change factor "INSTALLMENT", new installment amount should not be specified.';
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'P6',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF p_Change_Factor IN ('I','E') AND p_Tenor IS NULL THEN
      -- m_Retmsg := 'For change factor "INSTALLMENT", new tenure should be specified.';
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'P7',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF p_Change_Factor IN ('I','E') AND p_Tenor = 0 THEN
      --m_Retmsg := 'For change factor "INSTALLMENT", new tenure should be greater than 0.';
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'P8',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
      /*ELSIF p_Cycleday IS NULL THEN
      m_Retmsg := 'Cycle date should be specified.';*/
    END IF;
    /* Added for Reschedule on Partially Disbursed Cases */
    /* Start - Issue Fix : 147936 */
  
    /* Start - Month End as Due Date Enh. */
    If p_Cycleday = 0 Then
      m_CycleDay := to_number(to_char(to_date(p_eff_inst_dt, 'dd-mm-rrrr'),
                                      'DD'));
    Else
      m_CycleDay := p_Cycleday;
    End If;
    /* End - Month End as Due Date Enh. */
    IF /*p_Cycleday*/
     m_CycleDay <> -- Month End as Due Date Enh.
     to_number(to_char(to_date(p_eff_inst_dt, 'dd-mm-rrrr'), 'DD')) Then

      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'WRONG_CYCLEDAY',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;    
    End If;
  
    select l.c_repay_freq
      into m_Old_Repfreq
      FROM t_Lms_Loan_Account l
     WHERE l.Sz_Org_Code = p_Org_Code
       AND l.Sz_Loan_Account_No = p_Loan_Account_No;
    IF p_Repay_Freq = m_Old_Repfreq THEN
      m_Eff_Inst_Dt_Cnt := 1;
    Else
    Select count(1)
      into m_eff_inst_dt_cnt
      from dual
     where to_char(p_eff_inst_dt, 'DD/MM/RRRR') in
           (select regexp_substr(fun_lms_get_eff_inst_dts_list(p_org_code         => p_Org_Code,
                                                               p_loan_acc_no      => p_Loan_Account_No,
                                                               p_repay_freq       => p_Repay_Freq,
                                                               p_cycle_day        => p_Cycleday,
                                                               p_curr_eff_inst_dt => trunc(get_businessdate(p_Org_Code))/*pkg_general_services.get_next_inst_duedate(p_Org_Code,
                                                                                                                                p_Loan_Account_No,
                                                                                                                                1,
                                                                                                                                get_businessdate(p_Org_Code))*/),
                                 '[^,]+',
                                 1,
                                 level) Eff_Inst_Dates
              from dual
            connect by regexp_substr(fun_lms_get_eff_inst_dts_list(p_org_code         => p_Org_Code,
                                                                   p_loan_acc_no      => p_Loan_Account_No,
                                                                   p_repay_freq       => p_Repay_Freq,
                                                                   p_cycle_day        => p_Cycleday,
                                                                   p_curr_eff_inst_dt => trunc(get_businessdate(p_Org_Code))/*pkg_general_services.get_next_inst_duedate(p_Org_Code,
                                                                                                                                    p_Loan_Account_No,
                                                                                                                                    1,
                                                                                                                                    get_businessdate(p_Org_Code))*/),
                                     '[^,]+',
                                     1,
                                     level) is not null);
    END IF;
    /* End - Issue Fix : 147936 */
    If m_eff_inst_dt_cnt = 0 Then
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'EFFINSTDT',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    END IF;
    /* End for Reschedule on Partially Disbursed Cases */
    BEGIN
      SELECT MAX(Decode(Ts.c_Interest_Type, 'F', Ts.i_Installment_To, 0)) Inst_To,
             SUM(Decode(Ts.c_Interest_Type, 'F', 1, 0)) Fixed,
             SUM(Decode(Ts.c_Interest_Type, 'V', 1, 0)) Varb,
             MAX(Fun_Get_Skip_Curr_Installment(p_Org_Code,
                                               p_Loan_Account_No,
                                               Td.i_Tranche_No,
                                               '',
                                               Pkg_General_Services.Get_Business_Date(p_Org_Code))) Next_Inst
        INTO m_Instlmnt_To, m_Fixed, m_Variable, m_Next_Instlmnt
        FROM t_Lms_Tranche_Sch_Param Ts, t_Lms_Tranche_Dtls Td
       WHERE Td.Sz_Org_Code = Ts.Sz_Org_Code
         AND Td.Sz_Loan_Account_No = Ts.Sz_Loan_Account_No
         AND Td.i_Tranche_No = Ts.i_Tranche_No
         AND Td.c_Req_Status <> 'C'
         AND Ts.Sz_Org_Code = p_Org_Code
         AND Ts.i_Tranche_No = 1
         AND Ts.Sz_Loan_Account_No = p_Loan_Account_No;
    EXCEPTION
      WHEN OTHERS THEN
        m_Instlmnt_To   := 0;
        m_Next_Instlmnt := 0;
    END;
    IF m_Fixed >= 1 AND m_Variable >= 1 THEN
      IF m_Instlmnt_To >= m_Next_Instlmnt THEN
        --m_Retmsg := 'Reschedule is not allowed in fixed Interest period';
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'INTF',
                                             p_File_Name => p_Filename);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
    END IF;
    ----- ended by APRANSHU ----------------------------------------
    BEGIN
      select s.index_code,
       s.f_floor_int_rate,
       s.spread_code,
       s.f_pricing_idx_spread_rate,
       s.f_pricing_idx_max_offset
  INTO m_Index_Code,
       m_Index_Rate,
       m_Spread_Code,
       m_Idx_Spread_Rate,
       m_Max_Offsetrate
  from (SELECT distinct Ap.Sz_Pricing_Idx_Rate_Code   Index_Code,
                        Ap.f_Floor_Int_Rate,
                        Ap.Sz_Pricing_Idx_Spread_Code Spread_Code,
                        Ap.f_Pricing_Idx_Spread_Rate,
                        Ap.f_Pricing_Idx_Max_Offset
          FROM Prd_Vew_Prd_Details          Pd,
               Prd_Vew_Amort_Portfolio_Xref Ap,
               Prd_Vew_Product              Pa
         WHERE Pd.Sz_Org_Code = Ap.Sz_Org_Code
           AND Pd.Sz_Product_Code = Ap.Sz_Product_Code
           AND Pd.Sz_Product_Code = Pa.Sz_Product_Code
           AND Pd.Sz_Org_Code = Pa.Sz_Org_Code
           AND Pd.Sz_Org_Code = p_Org_Code
           AND Pd.Sz_Product_Code = m_Product_Code
           and ap.Sz_Pricing_Idx_Rate_Code is not null) S
 where rownum = 1;

      IF m_Index_Code IS NULL THEN
        --m_Retmsg := 'Index Code is required';
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'INDEX',
                                             p_File_Name => p_Filename);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        m_Index_Rate      := 0;
        m_Idx_Spread_Rate := 0;
        m_Max_Offsetrate  := 0;
    END;
    SELECT l.c_Repay_Freq Oldfrequency,
           l.c_Account_Status Accsts,
           l.c_Additional_Status Sts,
           Nvl(l.c_Final_Disb_Yn, 'N') Final_Disb,
           l.i_Cycleday i_Cycleday,
           l.Sz_Portfolio_Code Portcode,
           Nvl(l.f_Excess_Amt, 0)
      INTO m_Old_Repfreq,
           m_Accnt_Status,
           m_Add_Sts,
           m_Final_Disb,
           m_Cycle_Day,
           m_Portfolio,
           m_Excess_Amt
      FROM t_Lms_Loan_Account l
     WHERE l.Sz_Org_Code = p_Org_Code
       AND l.Sz_Loan_Account_No = p_Loan_Account_No;
    BEGIN
    SELECT Decode(Pd.Imintenor, 0, '', Pd.Imintenor),
           Decode(Pd.Imaxtenor, 0, '', Pd.Imaxtenor),
           Decode(Pd.Fmininstallment, 0, '', Pd.Fmininstallment),
           Decode(Pd.Fmaxinstallment, 0, '', Pd.Fmaxinstallment),
           Decode(Pd.Ffloorrate, 0, '', Pd.Ffloorrate),
           Decode(Pd.Fceilrate, 0, '', Pd.Fceilrate)
      INTO m_Min_Tenor,
           m_Max_Tenor,
           m_Min_Inst_Amt,
           m_Max_Inst_Amt,
           m_Min_Int_Rate,
           m_Max_Intrate
      FROM Prd_Mst_Product Pd
     WHERE Pd.Szorgid = Fun_Get_Org_Id(p_Org_Code) --p_Org_Code
       AND Pd.Szshortname = m_Product_Code;
    EXCEPTION
      WHEN OTHERS THEN
        m_Min_Tenor:=0;
           m_Max_Tenor:=0;
           m_Min_Inst_Amt:=0;
           m_Max_Inst_Amt:=0;
           m_Min_Int_Rate:=0;
           m_Max_Intrate:=0;
    END;
    SELECT Nvl(MIN(a.f_Locking_Period), 0)
      INTO m_Locking_Period
      FROM TABLE(Prd_Pkg_Product.Fun_Get_Product_Details(p_Org_Code,
                                                         m_Product_Code)) a;
    IF m_Accnt_Status <> 'L' THEN
      /* m_Retmsg := m_Retmsg ||
      '###ERROR:Rescheduling can be done only for Live Account ';*/
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'LV',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSE
      --NEWLY ADDED
      IF p_Tenor IS NOT NULL AND p_Installment_Amt IS NULL THEN
        IF p_Tenor < m_Min_Tenor THEN
          /* m_Retmsg := m_Retmsg ||
                      '###ERROR:Tenor should be greater than or equal to ' ||
          m_Min_Tenor;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'TN1',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Min_Tenor;
        END IF;
        IF p_Tenor > m_Max_Tenor THEN
          /*  m_Retmsg := m_Retmsg ||
                      '###ERROR:Tenor should be less than or equal to ' ||
          m_Max_Tenor;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'TN2',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Max_Tenor;
        END IF;
      END IF;
      IF p_Tenor IS NULL AND p_Installment_Amt IS NOT NULL THEN
        IF p_Installment_Amt < m_Min_Inst_Amt THEN
          /* m_Retmsg := m_Retmsg ||
                      '###ERROR:Installment Amount should be greater than ' ||
          m_Min_Inst_Amt;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'IN1',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Min_Inst_Amt;
        END IF;
        IF p_Installment_Amt > m_Max_Inst_Amt THEN
          /* m_Retmsg := m_Retmsg ||
                      '###ERROR:Installment Amount should be less than ' ||
          m_Max_Inst_Amt;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'IN2',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Max_Inst_Amt;
        END IF;
      END IF;
      IF m_Interestrate IS NOT NULL THEN
        IF m_Interestrate < m_Min_Int_Rate THEN
          /* m_Retmsg := m_Retmsg ||
                      '###ERROR:Interest Rate should be greater than ' ||
          m_Min_Int_Rate;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'INT1',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Min_Int_Rate;
        END IF;
        IF m_Interestrate > m_Max_Intrate THEN
          /* m_Retmsg := m_Retmsg ||
                      '###ERROR:Interest Rate should be less than ' ||
          m_Max_Intrate;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'INT2',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Max_Intrate;
        END IF;
      END IF;
      --END ADDED
      IF m_Portfolio = 'OL_PORT' THEN
        /*m_Retmsg := m_Retmsg ||
        '###ERROR:Reschedule is not allowed for Operating Lease ';*/
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'R1',
                                             p_File_Name => p_Filename);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
      /* Added for Reschedule on Partially Disbursed Cases */
      /*      IF m_Final_Disb = 'N' THEN
        \* m_Retmsg := m_Retmsg ||
                    '###ERROR:Partially disbursed Account cannot be rescheduled ';
        *\
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'R2',
                                             p_File_Name => p_Filename);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;*/
      /* End for Reschedule on Partially Disbursed Cases */
      IF m_Cycle_Day = 31 THEN
        /* m_Retmsg := m_Retmsg ||
                    '###ERROR:Cycle day can not be 31,select 1st as a cycle day instead of 31';
        */
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'R3',
                                             p_File_Name => p_Filename);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
      /*IF m_Interestrate > m_Max_Intrate THEN
        m_Retmsg := m_Retmsg ||
                    '###ERROR:Interest rate should not be more than maximum defined rate ';
      END IF;
      IF m_Interestrate < m_Min_Intrate THEN
        m_Retmsg := m_Retmsg ||
                    '###ERROR:Interest rate should not be less than minimum defined rate ';
      END IF;*/
      CASE
        WHEN (m_Accnt_Status = 'L' AND m_Add_Sts = 'PP') THEN
          /* m_Retmsg := m_Retmsg ||
          '###ERROR:Pending request exist for Prepayment can not make a new Reschedule request ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R4',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        WHEN (m_Accnt_Status = 'L' AND m_Add_Sts = 'PF') THEN
          /*m_Retmsg := m_Retmsg ||
          '###ERROR:Pending request exist for FullPrepayment can not make a new Reschedule request ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R5',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        WHEN (m_Accnt_Status = 'L' AND m_Add_Sts = 'PS') THEN
          /*  m_Retmsg := m_Retmsg ||
          '###ERROR:Selected Account cannot be reschedule as account is pending for settlement ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R6',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        WHEN (m_Accnt_Status = 'L' AND m_Add_Sts IN ('RS', 'RD')) THEN
          /* m_Retmsg := m_Retmsg ||
          '###ERROR:Selected Account cannot be reschedule as account is pending for Restructure DRE ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R7',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        WHEN (m_Accnt_Status = 'L' AND m_Add_Sts = 'RC') THEN
          /*m_Retmsg := m_Retmsg ||
          '###ERROR:Reschedule should not be allowed for the fraud customer ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R8',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        WHEN (m_Accnt_Status = 'L' AND m_Add_Sts = 'R') THEN
          /* m_Retmsg := m_Retmsg ||
          '###ERROR:Reschedule should not be allowed as assest is already resold';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R9',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        ELSE
          NULL;
      END CASE;
      SELECT COUNT(*)
        INTO Mf_Count
        FROM (SELECT Nvl(p.Sz_Lending_Type_Code, 'X') Sz_Lending_Type_Code,
                     r.Sz_Loan_Account_No Loan_Acc,
                     r.Sz_Org_Code
                FROM Prd_m_Portfolio           p,
                     Base_Org_Mst_Organization o,
                     t_Lms_Loan_Account        r
               WHERE p.Sz_Orgid = o.Szorg_Id
                 AND o.Szorg_Code = r.Sz_Org_Code
                 AND p.Sz_Portfolio_Code = r.Sz_Portfolio_Code) a
       WHERE a.Sz_Org_Code = p_Org_Code
         AND a.Loan_Acc = p_Loan_Account_No
         AND a.Sz_Lending_Type_Code = 'MF';
      IF Mf_Count > 0 THEN
        /*  m_Retmsg := m_Retmsg ||
        '###ERROR:Reschedule is not allowed for Microfinance';*/
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'R10',
                                             p_File_Name => p_Filename);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
      SELECT Nvl(Pkg_General_Services.Get_Bal_Tenor(p_Org_Code,
                                                    p_Loan_Account_No,
                                                    '',
                                                    p_Business_Date),
                 0) i_Baltenor
        INTO m_Bal_Tenor
        FROM Dual;
      IF m_Bal_Tenor = 0 THEN
        /*        m_Retmsg := m_Retmsg ||
        '###ERROR:Account cannot be reschedule as balance tenor is zero';*/
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'R11',
                                             p_File_Name => p_Filename);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
      SELECT s.f_Curr_Interestrate
        INTO m_New_Int_Rate
        FROM t_Lms_Tranche_Dtls s
       WHERE s.Sz_Org_Code = p_Org_Code
         AND s.Sz_Loan_Account_No = p_Loan_Account_No
         AND Rownum <= 1;
      IF m_New_Int_Rate > 100 THEN
        /* m_Retmsg := m_Retmsg ||
        '###ERROR:Interest Rate should not allowed more than 100%';*/
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'R12',
                                             p_File_Name => p_Filename);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
      SELECT Nvl(Pkg_Reschedule.Fun_Val_Retire_Age(p_Org_Code,
                                                   p_Loan_Account_No,
                                                   (SELECT MAX(Ts.i_Tranche_No)
                                                      FROM t_Lms_Tranche_Dtls Ts
                                                     WHERE Ts.Sz_Org_Code =
                                                           p_Org_Code
                                                       AND Ts.Sz_Loan_Account_No =
                                                           p_Loan_Account_No),
                                                   Pkg_General_Services.Get_Bal_Tenor(p_Org_Code,
                                                                                      p_Loan_Account_No,
                                                                                      '',
                                                                                      p_Business_Date)),
                 'Y') Flagretrage
        INTO m_Flagretrage
        FROM Dual;
      IF m_Flagretrage = 'N' THEN
        /* m_Retmsg := m_Retmsg ||
        '###ERROR:Please enter proper tenor as its exceed retirement age';*/
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'R13',
                                             p_File_Name => p_Filename);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
      SELECT Nvl(Pkg_Balances.Get_Total_Due(p_Org_Code, p_Loan_Account_No),
                 0)
        INTO m_Total_Due
        FROM Dual;
      SELECT Sz_Value
        INTO m_Value
        FROM m_Lms_Condition_Parameter n
       WHERE n.Sz_Condition = 'RESCH_AllOWED_FOR_DUE_ACCOUNTS';
      IF m_Total_Due > 0 AND m_Value = 'N' THEN
        /* m_Retmsg := m_Retmsg ||
        '###ERROR:Reschedule is not allowed for due accounts';*/
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'R14',
                                             p_File_Name => p_Filename);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
    END IF;
    ----newly added
    select COUNT(1)
    INTO M_BL_COUNT
    from t_lms_genbulk_reschedule t
    where t.sz_org_code=p_Org_Code
    and t.sz_loan_account_no=p_Loan_Account_No
    and t.sz_filename=p_Filename
    and t.c_variation_flag='BL';
    IF M_BL_COUNT>0 THEN
    BEGIN
      SELECT s.i_Srno,
             s.i_Month_Ballon Instno,
             s.f_Ballon_Pay   b_Value,
             s.f_Ballon_Adj   Rest_Adjust_Bln_Rsd
        INTO m_Bsrno, m_Bmonth, m_Bvalue, m_Badj
        FROM t_Lms_Balloon_Pay s
       WHERE s.Sz_Org_Code = p_Org_Code
         AND s.Sz_Loan_Account_No = p_Loan_Account_No
         AND s.i_Month_Ballon >=
             Fun_Get_Next_Installmentno(p_Org_Code,
                                        p_Loan_Account_No,
                                        '1',
                                        Fun_Getbusinessdate(p_Org_Code));
      IF (m_Bvalue <= 0 OR m_Bvalue > 100) THEN
        /* m_Retmsg := m_Retmsg ||
        '###ERROR:Balloon Percentage should be between 0 to 100% '; */
        m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                             p_Tran_Type => m_Module,
                                             p_Err_Code  => 'BALL',
                                             p_File_Name => p_Filename);
        m_Retmsg  := m_Retmsg || m_Err_Msg;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        m_Bvalue := 0;
    END;
     END IF;
   --issue fixed 145055
   BEGIN
    SELECT CASE
             WHEN (SELECT COUNT(1)
                     FROM t_Lms_Step_Pay Tb
                    WHERE Tb.Sz_Org_Code = Td.Sz_Org_Code
                      AND Tb.Sz_Loan_Account_No = Td.Sz_Loan_Account_No
                      AND Tb.i_Tranche_No = Td.i_Tranche_No
                      AND Tb.f_Step_Value = 0
                      AND Tb.Sz_Step_Basis = 3
                      AND Tb.Sz_Step_Mode = 0
                      AND Tb.Sz_Step_Adj = 1
                      AND Tb.Sz_Step_Up_Down = 0
                      AND Tb.i_Step_From_Month = 1
								  AND TB.I_STEP_TO_MONTH = (TD.I_TENOR - 1)) > 0 OR
                  (SELECT COUNT(1)
                 FROM T_LMS_PRODUCT_DTLS PD
                WHERE PD.SZ_ORG_CODE = TD.SZ_ORG_CODE
                  AND PD.SZ_LOAN_ACCOUNT_NO = TD.SZ_LOAN_ACCOUNT_NO
                  AND PD.I_TRANCHE_NO = TD.I_TRANCHE_NO
                  AND PD.I_INST_TYPE = 1) > 0 THEN
              'Y'
             ELSE
              'N'
           END Balloon_Yn
      INTO m_Balloon_Yn
      FROM t_Lms_Tranche_Dtls Td
     WHERE Td.Sz_Org_Code = p_Org_Code
       AND Td.Sz_Loan_Account_No = p_Loan_Account_No
       AND Td.c_Req_Status = 'L';
   EXCEPTION
     WHEN OTHERS THEN
       m_Balloon_Yn:='N';
  END;    
   IF p_Change_Factor IN ('I','E') THEN
    IF m_Balloon_Yn = 'Y' THEN
      /*m_Retmsg := m_Retmsg ||
      '###ERROR:Reschedule is not allowed for Installment Change, in case of Repayment Variation is Bullet Payment';*/
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'BALLR',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    END IF;
    END IF;
    ---variations validations
    --added for seperate frequency
    SELECT Decode(COUNT(1), 0, 'N', 'Y') Equatedprn_Yn
      INTO m_Prin_Freq
      FROM t_Lms_Product_Dtls p
     WHERE p.i_Inst_Type = 2
       AND p.Sz_Org_Code = p_Org_Code
       AND p.Sz_Loan_Account_No = p_Loan_Account_No;
    IF m_Prin_Freq = 'Y' THEN
      m_Change_Factor := 'T';
    END IF;
    IF m_Prin_Freq = 'Y' AND p_Change_Factor IN ('E', 'I') THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Change Factor Installment not allowed for Seperate frequency case';
    END IF;
    --ISSUE FIXED 144587
     begin
     SELECT Nvl(c_Variation_Flag, 'VR')
      INTO m_Variation_Flag
      FROM t_Lms_Genbulk_Reschedule t
     WHERE t.Sz_Org_Code = p_Org_Code
       AND t.Sz_Loan_Account_No = p_Loan_Account_No
       AND t.Row_Srno = p_Srno
       AND t.Sz_Filename = p_Filename
       and c_Variation_Flag is not null;
     exception
       when others then
         m_Variation_Flag:='VR';
     end;
    IF p_Change_Factor='T' AND  m_Variation_Flag IN ('BL','SK','ST') THEN
        m_Retmsg := m_Retmsg ||
                  '###ERROR:Variations not allowed for change factor Tenor(T)';
    END IF;
    IF m_Variation_Flag NOT IN ('BL','SK','ST','VR') THEN
        m_Retmsg := m_Retmsg ||
                  '###ERROR:Invalid Repayment Variation Flag:'||m_Variation_Flag;
    END IF;
    --END ISSUE
       
    IF (p_Change_Factor IN ('I', 'E') AND m_Prin_Freq = 'N' AND
       m_Variation_Flag IN ('BL', 'SK', 'ST')) THEN
      --VARIATIONS NOT ALLOWED IF PRODUCT CONFURED FOR SEPERATE REPAY FREQ
      Prc_Lms_Bulk_Resch_Varitions(p_Org_Code        => p_Org_Code,
                                   p_File_Name       => p_Filename,
                                   p_Loan_Account_No => p_Loan_Account_No,
                                   p_Srno            => p_Srno,
                                   p_Tenor           => To_Number(p_Tenor),
                                   p_Out_Xml         => m_Xml_Data,
                                   p_Ret_Msg         => m_Err_Msg);
      IF m_Err_Msg='T' THEN
         m_Err_Msg:=null;
      end if;
      m_Retmsg := m_Retmsg || m_Err_Msg;
    end if;
    ---end
    IF p_Level_Flag = 'LEVEL1' THEN
      UPDATE t_Lms_Genbulk_Reschedule t
         SET Sz_Errmsg = Sz_Errmsg || m_Retmsg
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Sz_Filename = p_Filename
         AND t.Row_Srno = p_Srno;
   ELSE
      UPDATE t_Lms_Genbulk_Reschedule t
         SET T.SZ_STAGE2_ERR = T.SZ_STAGE2_ERR  || m_Retmsg
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Sz_Filename = p_Filename
         AND t.Row_Srno = p_Srno;
    END IF;
    IF m_Retmsg IS NULL THEN
      p_Retmsg := 'T';
    ELSE
      p_Retmsg := m_Retmsg;
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      p_Retmsg := '-101';
      m_Proc_Err := 'LEVEL::' || p_Level_Flag || '@LAN::' ||
                    p_Loan_Account_No || '@File::' || p_Filename ||
                    '@Srno::' || p_Srno || '::' || Substr(SQLERRM, 1, 2000);
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Resch_Screen_Validations',
                                                    p_Errmsg   => m_Proc_Err);
  END Prc_Resch_Screen_Validations;
  PROCEDURE Prc_Lms_Bulk_Resch_Whatifval(p_Org_Code            VARCHAR2,
                                         p_Filename            IN VARCHAR2,
                                         p_Loan_Account_No     VARCHAR2,
                                         p_Srno                NUMBER,
                                         p_Repay_Freq          NUMBER,
                                         p_Change_Factor       CHAR,
                                         p_Cycleday            NUMBER,
                                         p_Installment_Amt     IN OUT NUMBER,
                                         p_Tenor               IN OUT NUMBER,
                                         p_Interestrate        NUMBER,
                                         p_Remarks             VARCHAR2,
                                         p_Offset              NUMBER,
                                         p_Reason              VARCHAR2,
                                         p_Equated_Prin        NUMBER,
                                         p_Business_Date       DATE,
                                         p_Userid              IN VARCHAR2 DEFAULT 'SYSADMIN',
                                         p_Level_Flag          IN VARCHAR2 DEFAULT NULL,
                                         p_Retmsg              OUT VARCHAR2,
                                         p_Tranche_No          OUT VARCHAR2,
                                         p_Trantype            OUT VARCHAR,
                                         p_Tranhead            OUT VARCHAR2,
                                         p_Osamount            OUT VARCHAR2,
                                         p_Waive_Amount        OUT VARCHAR2,
                                         p_Due_Amount          OUT VARCHAR2,
                                         p_Cap_Amount          OUT VARCHAR2,
                                         p_Total_Amount        OUT NUMBER,
                                         p_New_Product         OUT VARCHAR2,
                                         p_Interest_Rate       OUT NUMBER,
                                         p_Repayment_Prin_Freq OUT NUMBER, --Abhijeet 21-09-2016
                                         p_Variationxml        OUT CLOB,
                                         p_Adj_Bpi_Nxt_Inst    OUT VARCHAR2,
                                         p_Interest_Type       OUT VARCHAR2,
                                         p_Index_Code          OUT VARCHAR2,
                                         p_Index_Rate          OUT VARCHAR2,
                                         p_Offset_Rate         OUT VARCHAR2,
                                         p_Spread_Rate         OUT VARCHAR2,
                                         p_eff_inst_dt         IN DATE -- Added for Reschedule on Partially Disbursed Cases
                                         ) IS
    m_Old_Repfreq  t_Lms_Loan_Account.c_Repay_Freq%TYPE;
    m_Accnt_Status t_Lms_Loan_Account.c_Account_Status%TYPE;
    m_Add_Sts      t_Lms_Loan_Account.c_Additional_Status%TYPE;
    m_Final_Disb   t_Lms_Loan_Account.c_Final_Disb_Yn%TYPE;
    m_Cycle_Day    t_Lms_Loan_Account.i_Cycleday%TYPE;
    m_Portfolio    t_Lms_Loan_Account.Sz_Portfolio_Code%TYPE;
    m_Retmsg       VARCHAR2(4000);
    Mf_Count       NUMBER := 0;
    m_Bal_Tenor    NUMBER := 0;
    m_New_Int_Rate t_Lms_Tranche_Sch_Param.f_Interestrate%TYPE;
    m_Balloon_Yn   CHAR(1);
    m_Flagretrage  CHAR(1);
    m_Total_Due    NUMBER := 0;
    --p_Return_Msg   VARCHAR2(4000);
    m_Tenor        VARCHAR2(4000); --NUMBER := 0;
    m_Emi          VARCHAR2(4000):='0'; --NUMBER := 0;
    m_Xml_Data     CLOB; --VARCHAR2(4000);
    m_Product_Code t_Lms_Product_Dtls.Sz_Product_Code%TYPE;
    m_Interestrate NUMBER := p_Interestrate;
    m_Proc_Retmsg  VARCHAR2(4000);
    Err_Emi_Tenor_Cal EXCEPTION;
    Err_Amortz_Param EXCEPTION;
    Err_Reschedule_Req EXCEPTION;
    m_Validyn          VARCHAR2(100);
    m_Errormsg         VARCHAR2(4000);
    m_Errorval         VARCHAR2(4000);
    m_Skipclob         CLOB;
    m_Stepclob         CLOB;
    m_Ballonclob       CLOB;
    m_Ademiclob        NUMBER := 0;
    m_Variations       VARCHAR2(4000);
    m_Ballonpay_Amount NUMBER := 0;
    m_Trantype         VARCHAR2(4000);
    m_Tranhead         VARCHAR2(4000);
    m_Osamt            VARCHAR2(4000); --NUMBER := 0;
    m_Taxamt           VARCHAR2(4000); --NUMBER := 0;
    m_Tranche_No       VARCHAR2(4000);
    m_Waive_Amount     VARCHAR2(4000);
    m_Due_Amount       VARCHAR2(4000);
    m_Cap_Amount       VARCHAR2(4000);
    --m_Tot_Amount        NUMBER := 0;
    m_Total_Amount      NUMBER := 0;
    m_Bpi_Recovery_Flag VARCHAR2(100);
    m_Bsrno             t_Lms_Balloon_Pay.i_Srno%TYPE;
    m_Bmonth            t_Lms_Balloon_Pay.i_Month_Ballon%TYPE;
    m_Bvalue            t_Lms_Balloon_Pay.f_Ballon_Pay%TYPE;
    m_Badj              t_Lms_Balloon_Pay.f_Ballon_Adj%TYPE;
    m_Min_Tenor         Prd_Mst_Product.Imintenor%TYPE; -- t_Lms_Product_Dtls.i_Min_Tenor%TYPE;
    m_Max_Tenor         Prd_Mst_Product.Imaxtenor%TYPE; --t_Lms_Product_Dtls.i_Max_Tenor%TYPE;
    m_Min_Inst_Amt      Prd_Mst_Product.Fmininstallment%TYPE; --t_Lms_Product_Dtls.f_Min_Inst_Amt%TYPE;
    m_Max_Inst_Amt      Prd_Mst_Product.Fmaxinstallment%TYPE; --t_Lms_Product_Dtls.f_Max_Inst_Amt%TYPE;
    m_Min_Int_Rate      Prd_Mst_Product.Ffloorrate%TYPE; --t_Lms_Product_Dtls.f_Min_Int_Rate%TYPE;
    m_Locking_Period    NUMBER := 0;
    m_Max_Intrate       Prd_Mst_Product.Fceilrate%TYPE; --Prd_Vew_Product.f_Pricing_Fix_Max_Int_Rate%TYPE;
    m_Min_Intrate       Prd_Vew_Product.f_Pricing_Fix_Min_Int_Rate%TYPE;
    --m_Inst_From NUMBER := 0;
    --m_Inst_To   NUMBER := 0;
    --m_Step_Adj  t_Lms_Step_Pay.Sz_Step_Adj%TYPE;
    --m_Step_Value    t_Lms_Step_Pay.f_Step_Value%TYPE;
    --m_Skip_Instfrom NUMBER := 0;
    --m_Skip_Instto   NUMBER := 0;
    m_Interest_Type t_Lms_Product_Dtls.c_Interest_Type%TYPE;
    m_Index_Code      Prd_Vew_Amort_Portfolio_Xref.Sz_Pricing_Idx_Rate_Code%TYPE;
    m_Index_Rate      Prd_Vew_Amort_Portfolio_Xref.Sz_Pricing_Idx_Rate_Code%TYPE;
    m_Spread_Code     Prd_Vew_Amort_Portfolio_Xref.Sz_Pricing_Idx_Spread_Code%TYPE;
    m_Idx_Spread_Rate Prd_Vew_Amort_Portfolio_Xref.f_Pricing_Idx_Spread_Rate%TYPE;
    m_Max_Offsetrate  Prd_Vew_Amort_Portfolio_Xref.f_Pricing_Idx_Max_Offset%TYPE;
    m_Reterr          VARCHAR2(4000);
    Err_Ext_Resh_Val EXCEPTION;
    m_Old_Interestrate t_Lms_Tranche_Dtls.f_Curr_Interestrate%TYPE;
    m_Old_Freq         t_Lms_Product_Dtls.i_Compounding_Freq%TYPE;
    m_Old_Cycle        t_Lms_Loan_Account.i_Cycleday%TYPE;
    --m_Osamt_Fee        v_Lms_Head_Wise_Due.Osamt%TYPE;
    --m_Event_Chg        NUMBER := 0;
    --m_Event_Tax        NUMBER := 0;
    --m_Return_Msg       VARCHAR2(4000);
    m_Fixed    NUMBER := 0;
    m_Variable NUMBER := 0;
    ----added by APRANSHU
    m_Instlmnt_To   NUMBER := 0;
    m_Next_Instlmnt NUMBER := 0;
    m_Excess_Amt    t_Lms_Loan_Account.f_Excess_Amt%TYPE;
    m_Value         m_Lms_Condition_Parameter.Sz_Value%TYPE;
    m_Change_Factor VARCHAR2(100);
    m_Module        VARCHAR2(4000) := 'RESCHEDULE';
    m_Err_Msg       VARCHAR2(4000);
    --m_Xml           VARCHAR2(4000);
    m_Equated_Prin t_Lms_Product_Dtls.f_Equated_Prin_Frq%TYPE;
    m_Prin_Freq    CHAR(1) := 'N';
    m_Dateofcycle  VARCHAR2(4000);
    m_Lan_Count    NUMBER := 0;
    m_Proc_Err     VARCHAR2(4000);
    m_Business_Date  VARCHAR2(4000):=TO_CHAR(p_Business_Date);
	
    /* Start - RBL Issue Fix : 159691 */
    m_Min_Tenor1 PRD_MST_PRODUCT.IMINTENOR%TYPE; -- t_Lms_Product_Dtls.i_Min_Tenor%TYPE;
    m_Max_Tenor1 PRD_MST_PRODUCT.IMAXTENOR%TYPE; --t_Lms_Product_Dtls.i_Max_Tenor%TYPE;
    /* End - RBL Issue Fix : 159691 */
	
  BEGIN
    m_Retmsg := NULL;
    BEGIN
      SELECT t.Sz_Product_Code, t.c_Interest_Type, t.i_Compounding_Freq
        INTO m_Product_Code, m_Interest_Type, m_Old_Freq
        FROM t_Lms_Product_Dtls t
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No;
    EXCEPTION
      WHEN OTHERS THEN
        m_Product_Code  := NULL;
        m_Interest_Type := 'F';
    END;
    BEGIN
      SELECT s.f_Curr_Interestrate
        INTO m_Old_Interestrate
        FROM t_Lms_Tranche_Dtls s
       WHERE s.Sz_Org_Code = p_Org_Code
         AND s.Sz_Loan_Account_No = p_Loan_Account_No;
    EXCEPTION
      WHEN OTHERS THEN
        m_Old_Interestrate := 0;
    END;
    BEGIN
      SELECT l.i_Cycleday
        INTO m_Old_Cycle
        FROM t_Lms_Loan_Account l
       WHERE l.Sz_Org_Code = p_Org_Code
         AND l.Sz_Loan_Account_No = p_Loan_Account_No;
    EXCEPTION
      WHEN OTHERS THEN
        m_Old_Cycle := 0;
    END;
    IF m_Old_Cycle <> Nvl(p_Cycleday, '33') OR
       m_Old_Interestrate <> m_Interestrate OR m_Old_Freq <> p_Repay_Freq THEN
      m_Bpi_Recovery_Flag := 'Y';
    ELSE
      m_Bpi_Recovery_Flag := 'N';
    END IF;
    BEGIN
      SELECT MAX(Decode(Ts.c_Interest_Type, 'F', Ts.i_Installment_To, 0)) Inst_To,
             SUM(Decode(Ts.c_Interest_Type, 'F', 1, 0)) Fixed,
             SUM(Decode(Ts.c_Interest_Type, 'V', 1, 0)) Varb,
             MAX(Fun_Get_Skip_Curr_Installment(p_Org_Code,
                                               p_Loan_Account_No,
                                               Td.i_Tranche_No,
                                               '',
                                               Pkg_General_Services.Get_Business_Date(p_Org_Code))) Next_Inst
        INTO m_Instlmnt_To, m_Fixed, m_Variable, m_Next_Instlmnt
        FROM t_Lms_Tranche_Sch_Param Ts, t_Lms_Tranche_Dtls Td
       WHERE Td.Sz_Org_Code = Ts.Sz_Org_Code
         AND Td.Sz_Loan_Account_No = Ts.Sz_Loan_Account_No
         AND Td.i_Tranche_No = Ts.i_Tranche_No
         AND Td.c_Req_Status <> 'C'
         AND Ts.Sz_Org_Code = p_Org_Code
         AND Ts.i_Tranche_No = 1
         AND Ts.Sz_Loan_Account_No = p_Loan_Account_No;
    EXCEPTION
      WHEN OTHERS THEN
        m_Instlmnt_To   := 0;
        m_Next_Instlmnt := 0;
    END;
    BEGIN --ISSUE FIXED FOR VARIABLE 152714


      SELECT Sp.Sz_Index_Code Icode,
             Sp.f_Index Findex,
             Sp.f_Offset Foffset,
             Sp.f_Spread Fspread,
             Decode(Sp.Sz_Spread_Code,
                    NULL,
                    (SELECT x.Sz_Pricing_Idx_Spread_Code
                       FROM Prd_Amort_Portfolio_Xref x
                      WHERE x.Sz_Product_Code = Prd.Sz_Product_Code
                        AND x.Sz_Orgid = Fun_Get_Org_Id(p_Org_Code)),
                    Sp.Sz_Spread_Code) Sz_Spread_Code
        INTO m_Index_Code,
             m_Index_Rate,
             m_Max_Offsetrate,
             m_Idx_Spread_Rate,
             m_Spread_Code
        FROM t_Lms_Tranche_Dtls      Ts,
             t_Lms_Loan_Account      La,
             t_Lms_Product_Dtls      Pd,
             Prd_m_Product           Prd,
             t_Lms_Tranche_Sch_Param Sp
       WHERE Ts.Sz_Org_Code = La.Sz_Org_Code
         AND Ts.Sz_Org_Code = Pd.Sz_Org_Code
         AND Ts.Sz_Loan_Account_No = La.Sz_Loan_Account_No
         AND Ts.Sz_Loan_Account_No = Pd.Sz_Loan_Account_No
         AND Pd.Sz_Product_Code = Prd.Sz_Product_Code
         AND Ts.Sz_Org_Code = Fun_Get_Org_Code(Prd.Sz_Orgid)
         AND Ts.Sz_Org_Code = Sp.Sz_Org_Code
         AND Ts.Sz_Loan_Account_No = Sp.Sz_Loan_Account_No
         AND Ts.i_Tranche_No = Sp.i_Tranche_No
         AND Ts.i_Tranche_No = Pd.i_Tranche_No
         AND Ts.i_Curr_Installment_No BETWEEN Sp.i_Installment_From AND
             Sp.i_Installment_To
         AND Ts.Sz_Org_Code = p_Org_Code
         AND Ts.Sz_Loan_Account_No = p_Loan_Account_No
         AND Ts.c_Req_Status = 'L'
         AND Ts.i_Tranche_No = Nvl(p_Tranche_No, Ts.i_Tranche_No);
      /*
      SELECT Ap.Sz_Pricing_Idx_Rate_Code   Index_Code,
             Ap.f_Floor_Int_Rate,
             Ap.Sz_Pricing_Idx_Spread_Code Spread_Code,
             Ap.f_Pricing_Idx_Spread_Rate,
             Ap.f_Pricing_Idx_Max_Offset
        INTO m_Index_Code,
             m_Index_Rate,
             m_Spread_Code,
             m_Idx_Spread_Rate,
             m_Max_Offsetrate
        FROM Prd_Vew_Prd_Details          Pd,
             Prd_Vew_Amort_Portfolio_Xref Ap,
             Prd_Vew_Product              Pa
       WHERE Pd.Sz_Org_Code = Ap.Sz_Org_Code
         AND Pd.Sz_Product_Code = Ap.Sz_Product_Code
         AND Pd.Sz_Product_Code = Pa.Sz_Product_Code
         AND Pd.Sz_Org_Code = Pa.Sz_Org_Code
         AND Pd.Sz_Org_Code = p_Org_Code
         AND Pd.Sz_Product_Code = m_Product_Code;*/
    EXCEPTION
      WHEN OTHERS THEN
        m_Index_Rate      := 0;
        m_Idx_Spread_Rate := 0;
        m_Max_Offsetrate  := 0;
    END;
    SELECT l.c_Repay_Freq Oldfrequency,
           l.c_Account_Status Accsts,
           l.c_Additional_Status Sts,
           Nvl(l.c_Final_Disb_Yn, 'N') Final_Disb,
           l.i_Cycleday i_Cycleday,
           l.Sz_Portfolio_Code Portcode,
           Nvl(l.f_Excess_Amt, 0)
      INTO m_Old_Repfreq,
           m_Accnt_Status,
           m_Add_Sts,
           m_Final_Disb,
           m_Cycle_Day,
           m_Portfolio,
           m_Excess_Amt
      FROM t_Lms_Loan_Account l
     WHERE l.Sz_Org_Code = p_Org_Code
       AND l.Sz_Loan_Account_No = p_Loan_Account_No;
    SELECT Decode(Pd.Imintenor, 0, '', Pd.Imintenor),
           Decode(Pd.Imaxtenor, 0, '', Pd.Imaxtenor),
           Decode(Pd.Fmininstallment, 0, '', Pd.Fmininstallment),
           Decode(Pd.Fmaxinstallment, 0, '', Pd.Fmaxinstallment),
           Decode(Pd.Ffloorrate, 0, '', Pd.Ffloorrate),
           Decode(Pd.Fceilrate, 0, '', Pd.Fceilrate)
      INTO m_Min_Tenor,
           m_Max_Tenor,
           m_Min_Inst_Amt,
           m_Max_Inst_Amt,
           m_Min_Int_Rate,
           m_Max_Intrate
      FROM Prd_Mst_Product Pd
     WHERE Pd.Szorgid = Fun_Get_Org_Id(p_Org_Code) --p_Org_Code
       AND Pd.Szshortname = m_Product_Code;
    SELECT Nvl(MIN(a.f_Locking_Period), 0)
      INTO m_Locking_Period
      FROM TABLE(Prd_Pkg_Product.Fun_Get_Product_Details(p_Org_Code,
                                                         m_Product_Code)) a;
    ---CALL  Prc_Calculate_Emi_Tenor
    IF p_Change_Factor = 'T' THEN
      m_Emi           := nvl(p_Installment_Amt,0);
      m_Change_Factor := 'E';
    ELSE
      m_Tenor         := To_Char(nvl(p_Tenor,0));
      m_Change_Factor := p_Change_Factor;
    END IF;
    --added for seperate frequency
    SELECT Decode(COUNT(1), 0, 'N', 'Y') Equatedprn_Yn
      INTO m_Prin_Freq
      FROM t_Lms_Product_Dtls p
     WHERE p.i_Inst_Type = 2
       AND p.Sz_Org_Code = p_Org_Code
       AND p.Sz_Loan_Account_No = p_Loan_Account_No;
    IF m_Prin_Freq = 'Y' THEN
      m_Change_Factor := 'T';
    END IF;
    IF m_Prin_Freq = 'Y' AND p_Change_Factor IN ('E', 'I') THEN
      m_Retmsg := m_Retmsg ||
                  '###ERROR:Change Factor Installment not allowed for Seperate frequency case';
    END IF;
    --end
    IF m_Retmsg IS NULL THEN
      IF (p_Change_Factor IN ('I','E') AND m_Prin_Freq = 'N') THEN
        --VARIATIONS NOT ALLOWED IF PRODUCT CONFURED FOR SEPERATE REPAY FREQ
        Prc_Lms_Bulk_Resch_Varitions(p_Org_Code        => p_Org_Code,
                                     p_File_Name       => p_Filename,
                                     p_Loan_Account_No => p_Loan_Account_No,
                                     p_Srno            => p_Srno,
                                     p_Tenor           => To_Number(m_Tenor),
                                     p_Out_Xml         => m_Xml_Data,
                                     p_Ret_Msg         => m_Err_Msg);
        UPDATE t_Lms_Genbulk_Reschedule t
           SET t.Sz_Varition_Xml = m_Xml_Data
         WHERE t.Sz_Org_Code = p_Org_Code
           AND t.Sz_Loan_Account_No = p_Loan_Account_No
           AND t.Sz_Filename = p_Filename
           AND t.Row_Srno = p_Srno;
        IF m_Err_Msg <> 'T' THEN
          m_Retmsg := m_Retmsg || m_Err_Msg;
        END IF;
      ELSE --ISSUE FIXED FOR VARIABLE 152714


        /*IF m_Interest_Type = 'V' THEN
          m_Xml_Data := '<root LoanAccno=''' || p_Loan_Account_No ||
                        '''><tranche tno=''1'' /></root>';
        ELSE*/
          m_Xml_Data := NULL;
        /*END IF;*/
      END IF;
    END IF;
    IF m_Retmsg IS NULL THEN
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Resch_Extvalue(p_Org_Code        => p_Org_Code,
                                                         p_Loan_Account_No => p_Loan_Account_No,
                                                         p_Trantype        => m_Trantype,
                                                         p_Tranhead        => m_Tranhead,
                                                         p_Osamt           => m_Osamt,
                                                         p_Taxamt          => m_Taxamt,
                                                         p_Tranche_No      => m_Tranche_No,
                                                         p_Waive_Amt       => m_Waive_Amount,
                                                         p_Cap_Amt         => m_Cap_Amount,
                                                         p_Due_Amt         => m_Due_Amount,
                                                         p_Total_Amt       => m_Total_Amount,
                                                         p_Retmsg          => m_Reterr);
      IF m_Reterr <> 'T' THEN
        RAISE Err_Ext_Resh_Val;
      END IF;
    END IF;
    -- m_Total_Amount := m_Total_Amount - m_Excess_Amt;
    IF p_Installment_Amt > m_Total_Amount THEN
      /*m_Retmsg := m_Retmsg ||'###ERROR:New installment Amount greater than outstanding principal ';*/
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'R15',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    END IF;
    IF p_Cycleday IS NULL THEN
      SELECT To_Char(Pkg_Restructure.Get_Next_Installment_Dt(p_Org_Code,
                                                             p_Loan_Account_No,
                                                             Fun_Getbusinessdate(p_Org_Code),
                                                             m_Product_Code,
                                                             '',
                                                             p_Repay_Freq))
        INTO m_Dateofcycle
        FROM Dual;
      ----newly added
    ELSIF p_Cycleday IS NOT NULL THEN
      SELECT To_Char(Pkg_Restructure.Get_Next_Installment_Dt(p_Org_Code,
                                                             p_Loan_Account_No,
                                                             To_Date(Fun_Getbusinessdate(p_Org_Code)),
                                                             m_Product_Code,
                                                             p_Cycleday,
                                                             p_Repay_Freq),
                     'dd/mm/rrrr')
        INTO m_Dateofcycle
        FROM Dual;
    ELSE
      m_Dateofcycle := NULL;
    END IF;
    m_Dateofcycle := p_eff_inst_dt; -- Added for Reschedule on Partially Disbursed Cases
    if m_Retmsg is null then
    Pkg_Restructure.Prc_Calculate_Emi_Tenor(p_Org_Code             => p_Org_Code,
                                            p_Loan_Account_No      => p_Loan_Account_No,
                                            p_Tranche_No           => '1',
                                            p_Tenor_Unit           => '1',
                                            p_Loanamount           => m_Total_Amount, --p_Amount,
                                            p_New_Product          => m_Product_Code,
                                            p_Interestrate         => m_Interestrate,
                                            p_Tenor                => m_Tenor,
                                            p_Emi_Amt              => m_Emi,
                                            p_e_Or_t               => Nvl(p_Change_Factor,
                                                                          'E'),
                                            p_Frqeuncy             => p_Repay_Freq,
                                              --ISSUE FIXED FOR VARIABLE COMMENTED BELOW CODE 152714
                                              p_Interesttype         => NULL, /*CASE
                                                                        WHEN m_Interest_Type = 'F' THEN
                                                                         '0'
                                                                        WHEN m_Interest_Type = 'V' THEN
                                                                         '1'
                                                                        WHEN m_Interest_Type = 'M' THEN
                                                                         '2'
                                                                        ELSE
                                                                         NULL
                                                                                                                    END,*/ --NULL, --p_Interest_Type,
                                            p_Dateofdisbursement   => M_Business_Date,
                                            p_Dateofcycle          => m_Dateofcycle, --NULL,
                                            p_Interestbasis        => NULL,
                                            p_Amorttype            => NULL,
                                            p_Rest                 => p_Repay_Freq, --12,
                                            p_Installmenttype      => NULL,
                                            p_Compoundingfrequency => p_Repay_Freq,
                                            p_Xml_Data             => m_Xml_Data,
                                            p_Businessdate         => M_Business_Date,
                                            p_Return_Msg           => m_Proc_Retmsg,
                                            p_Offset               => NULL,
                                            p_Currency_Code        => 'INR',
                                              p_Cycleday             => p_Cycleday,
                                              p_Date_Format          => 'dd/MM/RRRR',
                                              p_VdtSim_Flag             => 'N'--VDT RESCHEDULE ENH.
                                              );

    m_Emi := Nvl(m_Emi, 0);
    IF m_Proc_Retmsg = 'AM001' THEN
      /*m_Retmsg := m_Retmsg ||
      '###ERROR:Please change the input parameters as it resulted in negative amort ';*/
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'R16',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF m_Proc_Retmsg = 'AM002' THEN
      /*m_Retmsg := m_Retmsg ||
      '###ERROR:Entered data is not valid, please re-check Tenor,interest,repayment variations provided ';*/
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'R17',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF m_Proc_Retmsg = 'AM001' THEN
      /*m_Retmsg := m_Retmsg ||
      '###ERROR:Please change the input parameters as it resulted in negative amort ';*/
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'R18',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF m_Proc_Retmsg = 'AM003' THEN
      /*m_Retmsg := m_Retmsg ||
      '###ERROR:Entered data is not valid, please re-check Tenor provided ';*/
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'R19',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF m_Proc_Retmsg = 'F' THEN
      /*m_Retmsg := m_Retmsg ||
      '###ERROR:Entered data is not valid, please re-check Tenor,interest,repayment variations provided ';*/
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'R20',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF m_Proc_Retmsg = 'rest.errmsg.instlamt' THEN
      ---added by APRANSHU
      /*m_Retmsg := m_Retmsg ||
      '###ERROR:New Installment should be less than or equal to New Finance Amount ';*/
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'R21',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSIF m_Proc_Retmsg = 'T' THEN
      m_Retmsg := NULL;
    END IF;
    END IF;
    IF m_Retmsg IS NULL THEN
      Prc_Lms_Bulk_Aayu_Err(p_Err_Msg => m_Proc_Retmsg);
      m_Retmsg := m_Retmsg || m_Proc_Retmsg;
    END IF;
    -----common for emitenor and
    /*IF m_Proc_Retmsg <> 'T' THEN
      RAISE Err_Emi_Tenor_Cal;
    END IF;*/
    IF m_Retmsg IS NULL THEN
	
          /* Start - RBL Issue fix : 159691 */
          select p.IMAXTENOR MAXTENOR, p.IMINTENOR MINTENOR
            Into m_max_tenor1, m_Min_Tenor1
            from PRD_MST_PRODUCT p
           where p.SZ_PRODUCT_CODE =
                 pkg_general_services.get_product_spclprd_code(p_Org_Code,
                                                               p_Loan_Account_No,
                                                               'PD',
                                                               null)
             AND P.SZ_ORGID = fun_get_org_id(p_Org_Code);
        
          If m_Tenor < m_Min_Tenor1 or m_Tenor > m_max_tenor1 Then
            m_Retmsg := '###ERROR:Tenor Should be in between Minimum- ' ||
                        m_Min_Tenor1 || '\Maximum-' || m_max_tenor1 ||
                        ' Tenor';
          End If;
          /* End - RBL Issue fix : 159691 */
		  
      Pkg_Restructure.Prd_Validate_Amortz_Param(p_Org_Code         => p_Org_Code,
                                                p_New_Product      => m_Product_Code,
                                                p_New_Tranche_No   => 1,
                                                p_New_Repay_Freq   => p_Repay_Freq,
                                                p_New_Tenor        => m_Tenor, --p_Tenor, --m_Tenor,
                                                p_New_Schm_Splprog => NULL,
                                                p_Scheme_Yn        => 'N',
                                                p_New_Inst_Amt     => m_Emi,
                                                p_New_Int_Rate     => m_Interestrate,
                                                p_Offset           => Nvl(p_Offset,
                                                                          0),
                                                p_Call_From        => 'RESCHEDULE',
                                                p_Loan_Account_No  => p_Loan_Account_No,
                                                p_Tranche_No       => 1,
                                                p_Tenor_Unit       => 1,
                                                p_Xml_Data         => m_Xml_Data,
                                                p_Validateyn       => 'Y',
                                                p_Validyn          => m_Validyn, ---OUT VARCHAR2,
                                                p_Errormsg         => m_Errormsg, --OUT VARCHAR2,
                                                p_Error_Val        => m_Errorval, --OUT VARCHAR2,
                                                p_Skip_Clob        => m_Skipclob, --OUT CLOB,
                                                p_Step_Clob        => m_Stepclob, --OUT CLOB,
                                                p_Ballon_Clob      => m_Ballonclob, --OUT CLOB,
                                                p_Advemi_Clob      => m_Ademiclob, --OUT NUMBER,
                                                p_Variations       => m_Variations, --OUT VARCHAR2,
                                                p_New_Loan_Amt     => m_Total_Amount, --p_Amount,
                                                p_Value_Date       => NULL,--VDT Reschedule Enh.
                                                p_Ballon_Last_Pay  => m_Ballonpay_Amount --OUT NUMBER
                                                );
      IF m_Validyn = 'REJECT' THEN
        IF m_Errormsg = 'PDCH01|2002' THEN
          /*m_Retmsg := m_Retmsg ||
          '###ERROR:Selected product does not exists ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R22',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        ELSIF m_Errormsg = 'PDCH01|2003' THEN
          /*m_Retmsg := m_Retmsg || '###ERROR:Selected product not active ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R23',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        ELSIF m_Errormsg = 'PDCH01|2004' THEN
          /*m_Retmsg := m_Retmsg ||
          '###ERROR:Selected product is not in valid period ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R24',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        ELSIF m_Errormsg = 'PDCH01|2007' THEN
          /*m_Retmsg := m_Retmsg ||
          '###ERROR:Portfolio of the selected product is not active ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R25',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        ELSIF m_Errormsg = 'PDCH02|' || m_Min_Tenor || '|' || p_Tenor THEN
          /*m_Retmsg := m_Retmsg ||
                      '###ERROR:Tenor should be greater than or equal to ' ||
          m_Min_Tenor;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R26',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Min_Tenor;
        ELSIF m_Errormsg = 'PDCH03|' || m_Max_Tenor || '|' || p_Tenor THEN
          /* m_Retmsg := m_Retmsg ||
                      '###ERROR:Tenor should be less than or equal to ' ||
          m_Max_Tenor;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R27',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Max_Tenor;
        ELSIF m_Errormsg = 'PDCH07|' || m_Min_Inst_Amt || '|' || m_Emi THEN
          /*m_Retmsg := m_Retmsg ||
                      '###ERROR:Installment Amount should be greater than ' ||
          m_Min_Inst_Amt;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R28',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Min_Inst_Amt;
        ELSIF m_Errormsg = 'PDCH08|' || m_Min_Inst_Amt || '|' || m_Emi THEN
          /*m_Retmsg := m_Retmsg ||
                      '###ERROR:Installment Amount should be less than ' ||
          m_Max_Inst_Amt;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R29',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Max_Inst_Amt;
        ELSIF m_Errormsg = 'PDCH09' THEN
          /*            m_Retmsg := m_Retmsg ||
          '###ERROR:Currency mismatch for selected Product and Account ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R30',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        ELSIF m_Errormsg = 'PDSKP01|2002' THEN
          /* m_Retmsg := m_Retmsg ||
          '###ERROR:Selected Product does not exists ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R31',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        ELSIF m_Errormsg = 'PDSKP01|2003' THEN
          --m_Retmsg := m_Retmsg || '###ERROR:Selected Product not active ';
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R32',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        ELSIF m_Errormsg = 'PDSKP01|2004' THEN
          /*m_Retmsg := m_Retmsg ||
          '###ERROR:Selected Product is not in valid period ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R33',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
        ELSIF m_Errormsg = 'PDAP01' THEN
          /* m_Retmsg := m_Retmsg ||
          '###ERROR:Selected product supports advance EMI at the end of the tenor ';*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R34',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg;
          /* ELSIF m_Errormsg LIKE 'PDCH04%' THEN
          ---added by APRANSHU
          m_Retmsg := m_Retmsg ||
                      '###ERROR:Finance Amount should be greater than or equal to ' ||
                      m_Min_Inst_Amt;*/
        ELSIF m_Errormsg LIKE 'PDCH05%' THEN
          ---added by APRANSHU
          /* m_Retmsg := m_Retmsg ||
                      '###ERROR:Finance Amount should be less than or equal to ' ||
          m_Total_Amount;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R35',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Total_Amount;
        ELSIF m_Errormsg LIKE 'PDCH06%' THEN
          ---added by APRANSHU
          /* m_Retmsg := m_Retmsg ||
                      '###ERROR:Interest Rate is not valid or should be greater than ' ||
          m_Min_Int_Rate;*/
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'R36',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Min_Int_Rate;
        ELSIF m_Errormsg LIKE 'PDSKP06|%' THEN
          m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                               p_Tran_Type => m_Module,
                                               p_Err_Code  => 'RSKIP',
                                               p_File_Name => p_Filename);
          m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' ||
                       Regexp_Substr(m_Errormsg, '[^|]+', 1, 2);
          /*   ----newly added
          ELSIF m_Errormsg = 'PDSKP02' THEN
            m_Retmsg := m_Retmsg ||
                        '###ERROR:Intermittent Skip for selected product is not allowed ';
          ELSIF m_Errormsg = 'PDSKP03' THEN
            m_Retmsg := m_Retmsg || '###ERROR:SKIP_TYPE ';
          ELSIF m_Errormsg = 'PDC10014' THEN
            m_Retmsg := m_Retmsg ||
                        '###ERROR:Initial Skip Not allowed for selected product ';
          ELSIF m_Errormsg = 'PDC10015' THEN
            m_Retmsg := m_Retmsg ||
                        '###ERROR:Skip Payment Basis- Intermittent can not be applicable for selected product ';
            ---*/
        ELSIF m_Errormsg = 'T' THEN
          m_Retmsg := NULL;
        ELSE
          IF m_Errormsg LIKE 'PDCH10|%' THEN
            m_Max_Offsetrate := Regexp_Substr(m_Errormsg, '[^|]+', 1, 2);
            IF p_Offset < m_Max_Offsetrate THEN
              /* m_Retmsg := m_Retmsg ||
                          '###ERROR:Offset value should be less than or equal to ' ||
              m_Max_Offsetrate;*/
              m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                   p_Tran_Type => m_Module,
                                                   p_Err_Code  => 'R37',
                                                   p_File_Name => p_Filename);
              m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Max_Offsetrate;
            END IF;
          ELSIF m_Errormsg LIKE 'PDCH11|%' THEN
            m_Max_Offsetrate := Regexp_Substr(m_Errormsg, '[^|]+', 1, 2);
            IF p_Offset < m_Max_Offsetrate THEN
              /*m_Retmsg := m_Retmsg ||
                          '###ERROR:Offset value should be greater than or equal to ' ||
              m_Max_Offsetrate;*/
              m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                                   p_Tran_Type => m_Module,
                                                   p_Err_Code  => 'R38',
                                                   p_File_Name => p_Filename);
              m_Retmsg  := m_Retmsg || m_Err_Msg || ' ' || m_Max_Offsetrate;
            END IF;
          END IF;
        END IF;
      END IF;
      --CALL RESTRUCTURE REQUEST
    END IF;
    SELECT Decode(COUNT(1), 0, 'N', 'Y') Equatedprn_Yn
      INTO m_Prin_Freq
      FROM t_Lms_Product_Dtls p
     WHERE p.i_Inst_Type = 2
       AND p.Sz_Org_Code = p_Org_Code
       AND p.Sz_Loan_Account_No = p_Loan_Account_No;
    IF m_Prin_Freq = 'Y' AND p_Equated_Prin IS NOT NULL THEN
      /* SELECT nvl(p_Equated_Prin,f_Equated_Prin_Frq)
        INTO m_Equated_Prin--m_Prin_Freq
        FROM t_Lms_Product_Dtls p
       WHERE p.i_Inst_Type = 2
         AND p.Sz_Org_Code = p_Org_Code
         AND p.Sz_Loan_Account_No = p_Loan_Account_No;
      m_Equated_Prin := Nvl(p_Equated_Prin,m_Equated_Prin);*/
      m_Equated_Prin := p_Equated_Prin;
    ELSIF m_Prin_Freq = 'Y' AND p_Equated_Prin IS NULL THEN
      m_Err_Msg := Fun_Lms_Bulk_Gen_Errmsg(p_Org_Code  => p_Org_Code,
                                           p_Tran_Type => m_Module,
                                           p_Err_Code  => 'PRINREPAY',
                                           p_File_Name => p_Filename);
      m_Retmsg  := m_Retmsg || m_Err_Msg;
    ELSE
      m_Equated_Prin := 0;
    END IF;
    IF p_Level_Flag = 'LEVEL1' THEN
      UPDATE t_Lms_Genbulk_Reschedule t
         SET Sz_Errmsg = Sz_Errmsg || m_Retmsg
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Sz_Filename = p_Filename
         AND t.Row_Srno = p_Srno;
    ELSE
      UPDATE t_Lms_Genbulk_Reschedule t
         SET t.Sz_Stage2_Err = t.Sz_Stage2_Err || m_Retmsg
       WHERE t.Sz_Org_Code = p_Org_Code
         AND t.Sz_Loan_Account_No = p_Loan_Account_No
         AND t.Sz_Filename = p_Filename
         AND t.Row_Srno = p_Srno;
    END IF;
    IF m_Retmsg IS NULL THEN
      p_Retmsg := 'T';
    ELSE
      p_Retmsg := m_Retmsg;
    END IF;
    -----out variables
    p_Tranche_No          := m_Tranche_No;
    p_Trantype            := m_Trantype;
    p_Tranhead            := m_Tranhead;
    p_Osamount            := m_Osamt;
    p_Waive_Amount        := m_Waive_Amount;
    p_Due_Amount          := m_Due_Amount;
    p_Cap_Amount          := m_Cap_Amount;
    p_Total_Amount        := m_Total_Amount;
    p_New_Product         := m_Product_Code;
    p_Installment_Amt     := m_Emi;
    p_Tenor               := m_Tenor;
    p_Interest_Rate       := m_Interestrate;
    p_Repayment_Prin_Freq := m_Equated_Prin;
    p_Variationxml        := m_Xml_Data;
    p_Adj_Bpi_Nxt_Inst    := m_Bpi_Recovery_Flag;
    p_Interest_Type       := m_Interest_Type;
    p_Index_Code          := m_Index_Code;
    p_Index_Rate          := m_Index_Rate;
    p_Offset_Rate         := p_Offset; -- m_Max_Offsetrate; -- Issue fix : 153960
    p_Spread_Rate         := m_Idx_Spread_Rate;
    ---end
  EXCEPTION
    WHEN OTHERS THEN
      p_Retmsg   := '-102';
      m_Proc_Err := 'LEVEL::' || p_Level_Flag || '@LAN::' ||
                    p_Loan_Account_No || '@File::' || p_Filename ||
                    '@Srno::' || p_Srno || '::' || Substr(SQLERRM, 1, 2000);
      Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Error_Log(p_Org_Code => p_Org_Code,
                                                    p_Object   => 'Pkg_Lms_Bulk_Operation.Prc_Lms_Bulk_Resch_Whatifval',
                                                    p_Errmsg   => m_Proc_Err);
  END Prc_Lms_Bulk_Resch_Whatifval;
  PROCEDURE Prc_Lms_Level1_Job(p_Org_Code  IN VARCHAR2,
                               p_Tran_Type IN VARCHAR2,
                               p_File_Name IN VARCHAR2, ---PIPE SEPERATED                                          
                               p_Retmsg    OUT VARCHAR2) IS
    m_Jobno  NUMBER;
  BEGIN
    Sys.Dbms_Job.Submit(m_Jobno,
                        'BEGIN PKG_LMS_BULK_OPERATION.Prc_Lms_Bulk_Level1_Validation(''' ||
                        p_Org_Code || ''',''' || p_Tran_Type || ''',''' ||
                        p_File_Name || '''); END;');
    COMMIT;
    p_Retmsg:='T';
  EXCEPTION
    WHEN OTHERS THEN
      p_Retmsg := Substr(SQLERRM, 1, 1000);
  END Prc_Lms_Level1_Job;
END Pkg_Lms_Bulk_Operation;
