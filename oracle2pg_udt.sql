/************************************************************************
 * oracle2pg_udt.sql - convert Oracle UDT for migration from Oracle to  *
 * PostgreSQL                                                           *
 *                                                                      *
 * @project    Oracle2PG Migration Toolkit                              *
 * @build_no   12                                                       *
 * @build_date $(BUILD_DATE)                                            *
 * @file       $(MAIN_SCRIPT_NAME)                                      *
 * @author     Igor Melnikov                                            *
 * @version    1.0.0                                                    *
 * @history                                                             *
 *  Igor Melnikov 18.11.2025 - Created                                  *
 *  Igor Melnikov 16.03.2026 - Adoption for advanced features           *
 ************************************************************************
 * Copyright: FelixDB Software                                          *
 * email: melnikov_ii@mail.ru                                           *
 ***********************************************************************/

set echo off
set define on
set verify off
set feedback off
set trim off
set trimspool off
set serveroutput on size unlimited format wrapped
set tab off
set term on
set sqlblanklines on 
set truncate off
set line 120
set heading off
set pagesize 0

spool oracle2pg_udt.log

--clear screen


define MAIN_SCRIPT_NAME=oracle2pg_udt.sql

var v_gVersion varchar2(32)
exec :v_gVersion := '1.0.0.0.0';

var v_xErrorFlag number
exec :v_xErrorFlag := 0;

var v_xNext char(1)
exec :v_xNext := 'Y';


var v_gOutput clob


column sql_file new_value SQL_FILE

var v_gSQL_file  varchar2(100)
exec :v_gSQL_file := 'ora_pg_udt.sql';



declare
  function getNowStr return varchar2 is
  begin
    return to_char(sysdate,'dd.mm.yyyy hh24:mi:ss');
  end;
begin
  dbms_output.put_line('=================================================================================================');
  dbms_output.put_line('Oracle2PG Migration Toolkit: Release ' || :v_gVersion || ' - Production on ' || getNowStr());
  dbms_output.new_line;
  dbms_output.put_line('&MAIN_SCRIPT_NAME - Convert Oracle UDT for migration from Oracle to PostgreSQL');
  dbms_output.new_line;
  dbms_output.put_line('Copyright (c) 2025,2026 Igor Melnikov.  All rights reserved.');
  dbms_output.new_line;
  dbms_output.new_line;
end;
/


declare

  cStringMaxLength constant simple_integer := 32767;

  subtype 
    String is varchar2(32767 char);

  type
    THashArrayOfString is table of String index by String;

  type
    TArrayOfString is table of String index by pls_integer;

  type
    TSetOfString is table of varchar2(1024);

  type
    TParameterInfo is record
    (
      Name           varchar2(32),      
      Description    varchar2(128),
      PossibleValues varchar2(128),
      Required       boolean,
      DefaultValue   varchar2(128),
      Visible        boolean,
      AndFlag        boolean
    );

  type
    TParameterInfoArray is table of TParameterInfo index by pls_integer;

  v_gParametersDefinition TParameterInfoArray;

  type
    TConfig is record
    (
      Schemas         TArrayOfString,
      ExcludeSchemas  TArrayOfString,
      SQLFileName     String,
      IsTrace         boolean
    );

  type
    TUDTInfo is record
    (
      owner      String,           
      type_name  String, 
      attributes pls_integer,
      methods    pls_integer,
      typecode   String
    );

  type
    TArrayUDTInfo is table of TUDTInfo index by pls_integer;

  type
    TUDTAttrInfo is record 
    (
      attr_name      String,
      attr_type_name String,
      length         pls_integer,
      precision      pls_integer,
      scale          pls_integer
    );

  type
    TUDTAttrInfoArray is table of TUDTAttrInfo index by pls_integer;


  gDebugFlag               constant boolean := true;           

  v_gConfig                TConfig;

  ECommandLineEmpty            exception;
  EParameterNameNotDefined     exception;
  ECommandLineHelp             exception;
  EAbort                       exception;
  ENotCorrectTablespaces       exception;
  EDatafileNotFoundInBackupset exception;

  v_xParameterValues       THashArrayOfString;
  v_gErrorText             String;
  v_gDebug                 boolean := false;

  procedure print(v_pStr in String) is
  begin
    dbms_output.put_line(v_pStr);
  end;

  procedure leave(v_pModuleName in varchar2) is
  begin
    if v_gDebug then
      print('Exit from module ' || v_pModuleName);
    end if;
  end;


  procedure enter(v_pModuleName in varchar2) is
  begin
    if v_gDebug then
      print('Enter to module ' || v_pModuleName);
    end if;
  end;


  procedure trace(v_pLine in String) is
  begin 
    if v_gDebug then
      print('Trace: ' || v_pLine);
    end if;
  end;


  procedure print(v_pArray in THashArrayOfString) is
    v_xCurrentIndex varchar2(32);
  begin
    if v_pArray.count = 0 then
      return;
    end if;

    v_xCurrentIndex := v_pArray.first;

    loop
      print(v_xCurrentIndex || ' => ' || v_pArray(v_xCurrentIndex));

      exit when v_xCurrentIndex = v_pArray.last;

      v_xCurrentIndex := v_pArray.next(v_xCurrentIndex);
    end loop;
  end;

 function getQuotedString(v_pArray in TArrayOfString) return String is
    v_xRes String := '';
  begin
    for v_xIndex in 1..v_pArray.count
    loop
      v_xRes := v_xRes || case when v_xIndex > 1 then ',' else '' end || '''' ||v_pArray(v_xIndex) || '''';
    end loop;
    return v_xRes;
  end;

  function getNowStr return varchar2 is
  begin
    return to_char(sysdate,'dd.mm.yyyy hh24:mi:ss');
  end;

  function getSplitStrings(v_pLine      in String,
                           v_pDelimiter in varchar2) return TArrayOfString is
    v_xResult   TArrayOfString;
    v_xCurrPos  pls_integer    := 1;
    v_xToken    String;
    v_xCurrChar char(1);
    v_xCount    pls_integer;
  begin
    if v_pLine is null then
      return v_xResult;
    end if;

    while v_xCurrPos <= length(v_pLine)
    loop
      v_xCurrChar := substr(v_pLine,v_xCurrPos,1);

      if v_xCurrChar = v_pDelimiter then
        v_xResult(v_xResult.Count+1) := v_xToken;
        v_xToken := '';
      else
        v_xToken := v_xToken || v_xCurrChar;
      end if;

      v_xCurrPos := v_xCurrPos + 1;
    end loop;

    if v_xToken is not null then
      v_xResult(v_xResult.Count+1) := v_xToken;
    end if;

    return v_xResult;
  end;

  function getArrayToComma(v_pArray in TArrayOfString) return String is
    v_xRes String;
  begin
    enter('getArrayToComma ...');

    for v_xIndex in 1..v_pArray.count
    loop
      v_xRes := v_xRes || ',' || v_pArray(v_xIndex);
      trace('length => ' || length(v_xRes));
    end loop;

    trace('getArrayToComma.Step1');

    if nvl(length(v_xRes),0) > 0 then
      trace('getArrayToComma.Step1.1');
      return substr(v_xRes,2);
    end if;

    trace('getArrayToComma.Step2');

    leave('getArrayToComma ...');

    trace('getArrayToComma.Step3');

    return v_xRes;
  end; 

  
  function getVarchar2s(v_pArray in TArrayOfString) return dbms_sql.varchar2s is
    v_xRes dbms_sql.varchar2s;
  begin
    if v_pArray is null or v_pArray.count = 0 then
      return v_xRes;
    end if; 

    for v_xIndex in 1..v_pArray.count
    loop
      v_xRes(v_xIndex) := v_pArray(v_xIndex);
    end loop;

    return v_xRes;
  end; 



  procedure print(v_pArray     in TArrayOfString,
                  v_pShowIndex in boolean := true) is
    v_xLine String;
  begin
    print('-------------------------------------------------------------------------------');
    if v_pArray is null or v_pArray.count = 0 then
      print('String Array is empry!!!');
      print('-------------------------------------------------------------------------------');
      return;
    end if;

    for v_xIndex in 1..v_pArray.count
    loop
      if v_pShowIndex then
        v_xLine := to_char(v_xIndex) || ' => ';
      end if;

      print(v_xLine || v_pArray(v_xIndex));
    end loop;

    print('-------------------------------------------------------------------------------');
  end;


  procedure print(v_pConfig in TConfig) is
  begin
    if not v_gDebug then
      return;
    end if;

    print('--------------          Passed parameters:       -------------------');
    print('--------------------------------------------------------------------');

  end;


  function getMinusStrings(v_pFirstArray  in out nocopy TArrayOfString,
                           v_pSecondArray in out nocopy TArrayOfString) return TArrayOfString is
    v_xRes       TArrayOfString;
    v_xFoundFlag boolean;
  begin
    for v_xFirstIndex in 1..v_pFirstArray.count
    loop
      v_xFoundFlag := false;

      for v_xSecondIndex in 1..v_pSecondArray.count 
      loop
        if v_pFirstArray(v_xFirstIndex) = v_pSecondArray(v_xSecondIndex) then
          v_xFoundFlag := true;
          exit;
        end if;
      end loop;

      if not v_xFoundFlag then
        v_xRes(v_xRes.count+1) := v_pFirstArray(v_xFirstIndex);
      end if;
    end loop;

    return v_xRes;
  end;
  

  function getUserDefinedSchemas return TArrayOfString is
    v_xRes TArrayOfString;
  begin
    for fUser in (select
                    username
                  from
                    dba_users
                  where
                    username not in ('WMSYS','SYS','SYSTEM','AUDSYS','MDSYS','CTXSYS','XDB','WKSYS','LBACSYS','OLAPSYS','DMSYS','ODM','ORDSYS','ORDDATA', 
                                     'ORDPLUGINS','SI_INFORMTN_SCHEMA','OUTLN','DBSNMP','MGMT_VIEW','OWBSYS','XS$NULL',  'SPATIAL_WFS_ADMIN_USR',
                                     'TSMSYS','WKPROXY','ORACLE_OCM','SPATIAL_CSW_ADMIN_USR','SYSMAN','DIP','EXFSYS','ANONYMOUS','MDDATA','WK_TEST','APPQOSSYS',
                                     'FLOWS_FILES','APEX_040200','APEX_PUBLIC_USER','OJVMSYS','GSMADMIN_INTERNAL','APEX_180200',
                                     'SYS$UMF',  'DBSFWUSER', 'GGSYS', 'GSMCATUSER', 'REMOTE_SCHEDULER_AGENT', 'SYSBACKUP','GSMUSER','SYSRAC','SYSKM','APEX_INSTANCE_ADMIN_USER','SYSDG'))
    loop
      v_xRes(v_xRes.count + 1) := fUser.username;
    end loop;

    return v_xRes;
  end;


  function getUDT(v_pSchemaName in String) return TArrayUDTInfo is
    v_xRes  TArrayUDTInfo;
    v_xType TUDTInfo;
  begin
    for fType in (select 
                    dt.owner,
                    dt.type_name,
                    dt.attributes,
                    dt.methods,
                    dt.typecode
                  from 
                    dba_types dt
                  where 
                    dt.typecode in ('OBJECT', 'COLLECTION') and
                    dt.owner = v_pSchemaName)
    loop
      v_xType.owner      := fType.owner;
      v_xType.type_name  := fType.type_name;
      v_xType.attributes := fType.attributes;
      v_xType.methods    := fType.methods;  
      v_xType.typecode   := fType.typecode;  

      v_xRes(v_xRes.count+1) := v_xType;
    end loop;

    return v_xRes;
  end;


  function getUDTAttrInfo(v_pSchemaName in String,
                          v_pTypeName   in String) return TUDTAttrInfoArray is
    v_xRes         TUDTAttrInfoArray;
    v_xUDTAttrInfo TUDTAttrInfo;
  begin
    for fUDTAttrInfo in (select
                           dta.attr_name,
                           dta.attr_type_name,
                           dta.length,
                           dta.precision,
                           dta.scale
                         from 
                           dba_type_attrs dta
                         where 
                           dta.owner            = v_pSchemaName and
                           upper(dta.type_name) = upper(v_pTypeName)
                         order by 
                           dta.attr_no)
    loop
      v_xUDTAttrInfo.attr_name      := fUDTAttrInfo.attr_name;
      v_xUDTAttrInfo.attr_type_name := fUDTAttrInfo.attr_type_name;
      v_xUDTAttrInfo.length         := fUDTAttrInfo.length;
      v_xUDTAttrInfo.precision      := fUDTAttrInfo.precision;
      v_xUDTAttrInfo.scale          := fUDTAttrInfo.scale;

      v_xRes(v_xRes.count+1) := v_xUDTAttrInfo;
    end loop;

    return v_xRes;
  end;


  procedure processUDT(v_pSchemas in TArrayOfString) is
    v_xArrayUDTInfo     TArrayUDTInfo;
    v_xUDTAttrInfoArray TUDTAttrInfoArray;
    v_xSchemaName       String;
  begin
    for v_xIndex in 1..v_pSchemas.count
    loop
      v_xSchemaName := v_pSchemas(v_xIndex);
      v_xArrayUDTInfo := getUDT(v_xSchemaName);

      continue when (v_xArrayUDTInfo.count = 0);
      trace('Found ' || v_xArrayUDTInfo.count || ' UDTs in schema ' || v_xSchemaName);

      --1. For each UDT, we generate a function to emulate the default constructor

      for v_xTypeIndex in 1..v_xArrayUDTInfo.count
      loop
        -- for Collection need specific constrauctor
        continue when (v_xArrayUDTInfo(v_xTypeIndex).typecode = 'COLLECTION');

        v_xUDTAttrInfoArray := getUDTAttrInfo(v_xSchemaName,v_xArrayUDTInfo(v_xTypeIndex).type_name);
        trace('  For type ' || v_xArrayUDTInfo(v_xTypeIndex).type_name || ' have ' || v_xUDTAttrInfoArray.count || ' attributes');
      end loop;

    end loop;
  end;

  procedure initParametersDefinition is
    procedure addParameter(v_pName           in varchar2,
                           v_pDescription    in varchar2,
                           v_pPossibleValues in varchar2,
                           v_pRequired       in boolean,
                           v_pDefaultValue   in varchar2,
                           v_pVisible        in boolean,
                           v_pAndFlag        in boolean) is
      v_xParameterInfo TParameterInfo;
    begin
      v_xParameterInfo.Name           := v_pName;          
      v_xParameterInfo.Description    := v_pDescription;    
      v_xParameterInfo.PossibleValues := v_pPossibleValues;
      v_xParameterInfo.Required       := v_pRequired;      
      v_xParameterInfo.DefaultValue   := v_pDefaultValue;  
      v_xParameterInfo.Visible        := v_pVisible;       
      v_xParameterInfo.AndFlag        := v_pAndFlag;

      v_gParametersDefinition(v_gParametersDefinition.count+1) := v_xParameterInfo;
    end;

  begin
    addParameter('SCHEMAS','Schemas for migration to PostgreSQL, ALL - all user-defined schemas','',false,'ALL',true,true);
    addParameter('EXCLUDE_SCHEMAS','Schemas excluded from migration','',false,'',true,true);
    addParameter('SQL_FILE','SQL-script file name','',false,'ora_udt.sql',true,true);
    addParameter('HELP','print this message','Y,N',false,'N',true,false);
    addParameter('DEBUG','Debug mode','Y,N',false,'N',true,false);
  end;


  procedure printHelp is
    v_xParameterNameLengthMax pls_integer := 0;
    v_xLine                   varchar2(512);
  begin
    print('You can control how &MAIN_SCRIPT_NAME runs by entering the "&MAIN_SCRIPT_NAME" command followed');
    print('by various arguments. To specify parameters, you use keywords:');
    dbms_output.new_line;
    print('     Format:  @&MAIN_SCRIPT_NAME parameter1=value1 parameter2=value2');
    dbms_output.new_line;
    print('     Example: @&MAIN_SCRIPT_NAME SCHEMAS=users,users_ind SQL_FILE=udt_v1.sql');
    print('              @&MAIN_SCRIPT_NAME EXCLUDE_SCHEMAS=SCOTT SQL_FILE=udt_v2.sql');
    dbms_output.new_line;
    print('Keyword          Description (Default)');
    print('--------------------------------------------------------');

    for v_xIndex in 1..v_gParametersDefinition.count
    loop
      if v_xParameterNameLengthMax < length(v_gParametersDefinition(v_xIndex).Name) then
        v_xParameterNameLengthMax := length(v_gParametersDefinition(v_xIndex).Name);
      end if;
    end loop;

    for v_xIndex in 1..v_gParametersDefinition.count
    loop
      if not v_gParametersDefinition(v_xIndex).visible then
        goto next_iteration;
      end if;

      v_xLine := rpad(v_gParametersDefinition(v_xIndex).Name,v_xParameterNameLengthMax,' ') || '  ' || 
                 v_gParametersDefinition(v_xIndex).Description;

      if v_gParametersDefinition(v_xIndex).PossibleValues is not null then
        v_xLine := v_xLine || ': ';

        if not v_gParametersDefinition(v_xIndex).AndFlag then
          v_xLine := v_xLine || replace(v_gParametersDefinition(v_xIndex).PossibleValues,',','/');
        else
          v_xLine := v_xLine || v_gParametersDefinition(v_xIndex).PossibleValues;
        end if;
      end if;

      if v_gParametersDefinition(v_xIndex).DefaultValue is not null then
        v_xLine := v_xLine || ' (' || v_gParametersDefinition(v_xIndex).DefaultValue || ')';
      end if;

      print(v_xLine);

    <<next_iteration>>
      null;
    end loop;
  end;


  function getParameterValue(v_pParameterName in String) return String is
    function getParameterDefaultValue(v_pParameterName in String) return String is
    begin
      for v_xIndex in 1..v_gParametersDefinition.count
      loop
        if v_gParametersDefinition(v_xIndex).Name = upper(v_pParameterName) then
          return v_gParametersDefinition(v_xIndex).DefaultValue;
        end if;
      end loop;
    end;
  begin
    if not v_xParameterValues.exists(upper(v_pParameterName)) then
      return getParameterDefaultValue(v_pParameterName);
    end if;
      
    return v_xParameterValues(upper(v_pParameterName));
    
  end;


  procedure parseCommandLine is
    v_xCommandLine     varchar2(4000);
    v_xParameterItems  TArrayOfString;
    v_xPos             pls_integer;
    v_xCurrentItem     varchar2(4000);

    /*
      Pack command line - delete blank symbols
    */
    procedure packCommandLine is
      v_xCount           pls_integer;
      v_xIndex           pls_integer := 0;
      v_xTmpCommandLine  varchar2(4000);
      v_xCurrentChar     char(1);
    begin
      v_xCommandLine := trim('&1')  || ' ' || trim('&2')  || ' ' || 
                        trim('&3')  || ' ' || trim('&4')  || ' ' || 
                        trim('&5')  || ' ' || trim('&6')  || ' ' || 
                        trim('&7')  || ' ' || trim('&8')  || ' ' || 
                        trim('&9')  || ' ' || trim('&10');

  
      v_xCommandLine := trim(v_xCommandLine);
  
      v_xCount := nvl(length(v_xCommandLine),0);
  
      if v_xCount = 0 then 
        return;
      end if;
    end;

    function isHelp return boolean is
    begin
      if v_xParameterValues.exists('HELP') then
        if upper(v_xParameterValues('HELP')) = 'Y' then
          return true;
        end if;
      end if;

      return false;
    end;


    procedure checkCommandLine is
      v_xCurrentValues  TArrayOfString;
      v_xPossibleValues TArrayOfString;
      v_xParameterName  varchar2(32);
      v_xFoundFlag      boolean;

      -------  check parameter name correctivity ------
      procedure checkParameterName is
      begin
        v_xParameterName := v_xParameterValues.first;
        for v_xIndex in 1..v_xParameterValues.count
        loop
          v_xFoundFlag := false;
          for v_xIndexDefinition in 1..v_gParametersDefinition.count
          loop 
            if v_xParameterName = v_gParametersDefinition(v_xIndexDefinition).name then
              v_xFoundFlag := true;
              exit;
            end if;
          end loop;
     
          if not v_xFoundFlag then
            print('ERROR: unknown parameter ' || v_xParameterName);
            raise EAbort;
          end if;
     
          v_xParameterName := v_xParameterValues.next(v_xParameterName);
        end loop;
      end;

      -------  check required parameters ------
      procedure checkRequiredParameters is
      begin
        for v_xIndex in 1..v_gParametersDefinition.count
        loop
          if v_gParametersDefinition(v_xIndex).Required then
            if not v_xParameterValues.exists(v_gParametersDefinition(v_xIndex).Name) then
              print('ERROR: not defined value for parameter ' || v_gParametersDefinition(v_xIndex).Name);
              :v_xErrorFlag := 5;
              raise EAbort;
            end if;
          end if;
        end loop;
      end;


      -------  check possible values for parameters ------
      procedure checkPossibleValues is
      begin
        enter('checkPossibleValues');
        for v_xIndex in 1..v_gParametersDefinition.count
        loop
          if v_gParametersDefinition(v_xIndex).PossibleValues is not null then
            if v_xParameterValues.exists(v_gParametersDefinition(v_xIndex).Name) then
  
              if not v_gParametersDefinition(v_xIndex).AndFlag then
                if instr(v_xParameterValues(v_gParametersDefinition(v_xIndex).Name),',') > 0 then
                  print('ERROR: for parameter ' || v_gParametersDefinition(v_xIndex).Name ||
                                       ' possible only one values from ' || v_gParametersDefinition(v_xIndex).PossibleValues);
                  :v_xErrorFlag := 5;
                  raise EAbort;
                end if;
              end if;
  
              v_xCurrentValues  := getSplitStrings(upper(v_xParameterValues(v_gParametersDefinition(v_xIndex).Name)),',');
              v_xPossibleValues := getSplitStrings(v_gParametersDefinition(v_xIndex).PossibleValues,',');

              trace('v_xCurrentValues.count => ' || v_xCurrentValues.count);
  
              for v_xCurrentIndex in 1..v_xCurrentValues.count
              loop
                v_xFoundFlag := false;
                for v_xPossibleIndex in 1..v_xPossibleValues.count
                loop
                  if trim(v_xCurrentValues(v_xCurrentIndex)) = v_xPossibleValues(v_xPossibleIndex) then
                    v_xFoundFlag := true;
                    exit;
                  end if;
                end loop;
  
                if not v_xFoundFlag then
                  print('ERROR: not possible value "' || v_xCurrentValues(v_xCurrentIndex) || 
                                       '" for parameter ' || v_gParametersDefinition(v_xIndex).Name       ||
                                       ' must be one of: ' || v_gParametersDefinition(v_xIndex).PossibleValues);
                  raise EAbort;
                end if;
              end loop;
  
            end if;
          end if;
        end loop;

        leave('checkPossibleValues');
      end;


      procedure readConfig is
      begin
        if upper(getParameterValue('DEBUG')) = 'Y' then
          v_gDebug := true;
          print('Set debug to true');
        end if;

        if upper(getParameterValue('SCHEMAS')) = 'ALL' then
          trace('call getUserDefinedTablespaces');
          v_gConfig.Schemas := getUserDefinedSchemas();
        else
          v_gConfig.Schemas := getSplitStrings(upper(v_xParameterValues('SCHEMAS')),',');
        end if;

        if nvl(length(trim(getParameterValue('EXCLUDE_SCHEMAS'))),0) > 0  then

          if getParameterValue('SCHEMAS') != 'ALL' then
            print('ERROR: parameters SCHEMAS and EXCLUDE_SCHEMAS cannot use together');
            :v_xErrorFlag := 5;
            raise EAbort;
          end if;

          v_gConfig.ExcludeSchemas := getSplitStrings(upper(v_xParameterValues('EXCLUDE_SCHEMAS')),',');

          v_gConfig.Schemas := getMinusStrings(v_gConfig.Schemas, v_gConfig.ExcludeSchemas);
        end if;

        v_gConfig.SQLFileName := getParameterValue('SQL_FILE');
      end;

    begin
      checkParameterName;
      checkPossibleValues;
      checkRequiredParameters;

      readConfig;
    end;

  begin /*  p a r s e C o m m a n d L i n e  */
    packCommandLine;

    if trim(v_xCommandLine) is null then
      --check if have required parameters:
      for v_xIndex in 1..v_gParametersDefinition.count
      loop
        if v_gParametersDefinition(v_xIndex).Required then
          raise ECommandLineEmpty;
        end if;
      end loop;
    end if;

    v_xParameterItems := getSplitStrings(v_xCommandLine,' ');
    for v_xIndex in 1..v_xParameterItems.count
    loop
      v_xCurrentItem := trim(v_xParameterItems(v_xIndex));
      v_xPos := instr(v_xCurrentItem,'=');

      if v_xPos > 0 then
        if trim(substr(v_xCurrentItem,1,v_xPos-1)) is null then
          raise EParameterNameNotDefined;
        end if;

        v_xParameterValues(upper(trim(substr(v_xCurrentItem,1,v_xPos-1)))) := trim(substr(v_xCurrentItem,v_xPos+1));
      else
        v_xParameterValues(upper(v_xCurrentItem)) := '';
      end if; 
    end loop;

    if isHelp then 
      raise ECommandLineHelp;
    end if;

    checkCommandLine;
  end;

  procedure checkParameterValuesCorrect is
    v_xStr   String;
    v_xArray TArrayofString;
  begin
    null;
  end;


begin  /*  m  a  i  n  */
  initParametersDefinition;
  parseCommandLine;

  print(v_gConfig);

  checkParameterValuesCorrect;
  processUDT(v_gConfig.Schemas);


exception
  when ECommandLineEmpty        then
    print('ERROR: Parameters not defined, type key ''@&MAIN_SCRIPT_NAME HELP=Y'' for help');
    :v_xErrorFlag := 1; 
  when EParameterNameNotDefined then
    print('ERROR: Parameter name is empty before symbol ''=''');
    :v_xErrorFlag := 5; 
  when ECommandLineHelp         then
    printHelp;
    :v_xErrorFlag := 0; 
  when ENotCorrectTablespaces   then
    print('ERROR: ' || v_gErrorText);
    :v_xErrorFlag := 5; 
  when EDatafileNotFoundInBackupset then
    print('ERROR: ' || v_gErrorText);
    :v_xErrorFlag := 5; 
  when EAbort                   then
    :v_xErrorFlag := 5;

end;
/


prompt Done
prompt 
prompt 

begin
   if :v_xErrorFlag = 0 then
     dbms_output.put_line('Successfully finished.');

     return;
   end if;

   dbms_output.put_line('Finished with errors!');
end;
/

prompt 
prompt 

spool off

set term off

/************************************************************************
 * init.sql - initialization for sqlplus script parameters              *
 *                                                                      *
 * @project    Oracle2PG Migration Toolkit                              *
 * @file       init.sql                                                 *
 * @author     Igor Melnikov                                            *
 * @version    1.0.0                                                    *
 * @history                                                             *
 *  Igor Melnikov 18.11.2025 - created                                  *
 ************************************************************************
 * Copyright: FelixDB Software                                          *
 * email: melnikov_ii@mail.ru                                           *
 ***********************************************************************/

set feedback off

define 1=" "
define 2=" "
define 3=" "
define 4=" "
define 5=" "
define 6=" "
define 7=" "
define 8=" "
define 9=" "
define 10=" "
define 11=" "
define 12=" "
define 13=" "
define 14=" "
define 15=" "
define 16=" "
define 17=" "
define 18=" "
define 19=" "
define 20=" "


set echo off 
define NOW_STR= 

column NOW_STR new_value NOW_STR

select
  to_char(sysdate,'dd.mm.yyyy hh24:mi:ss') as NOW_STR
from
  dual;


prompt Oracle2PG Migration Toolkit: Release 1.0.0.0.0 - Production on &NOW_STR
prompt 
prompt Copyright (c) 2025, Igor Melnikov.  All rights reserved.                                                                
prompt
prompt Successfully initialized!

prompt 


set term on
