create or replace PACKAGE BODY PROCESS_4004
AS


PROCEDURE REBATE_NOTIFICATIONS
AS
  loc_app_check        NUMBER;
  loc_application_id   NUMBER;
  loc_application_type VARCHAR2(30);
  loc_applicant_email TRRP_REBATES.R_APPLICANTEMAIL%TYPE;
   loc_contractor_email TRRP_REBATES.R_APPLICANTEMAIL%TYPE;
  loc_mail_type VARCHAR2(1 CHAR);
  loc_email_content CLOB:=NULL;
  loc_email_header VARCHAR2(4000 CHAR);
  loc_email_body   VARCHAR2(4000 CHAR);
  loc_email_footer VARCHAR2(4000 CHAR);
  loc_custdesc     VARCHAR2(4000 CHAR);
  Temp_Custdesc    VARCHAR2(4000 CHAR):=NULL;
  loc_reject_code  VARCHAR2(1000)     :=NULL;
  temp_reject_code  VARCHAR2(1000);
  loc_appliance_type  VARCHAR2(1000)  :=NULL;
  temp_appliance_type  varchar2(1000) :=NULL;
  loc_contract			VARCHAR2(100);
  loc_payee   number(6);
  landfname varchar2(60);
  landlname varchar2(60);
  last_notif_date    trrp_rebate_notifications.notification_date%type;
  Date_Diff Number;
  Loc_Reccount Number;
  loc_mailstatus number(1);
   loc_agency  varchar(50); 
   loc_new_code_count number:=0;
  loc_old_code_count number:=0;
  compare_code number:=0;
  v_count number := 0 ;
BEGIN
  
  dbms_output.enable();
  dbms_output.put_line  ('Check this status');
  EXECUTE IMMEDIATE 'truncate table temp_rebate_notification';
  FOR i IN
  (SELECT contractor_id as Application_Id
    FROM mdrp_contractor_profile
    where ((Application_review in ('Rejected','RequestInfo'))
    or contractor_id  in ( select  t2.application_id from MDRP_CONTRACTOR_PROFILE t1  inner  join  trrp_rebate_status t2  on 
    (t1.contractor_Id =  t2.application_id)  
    where  t2.R_Reject_statuscode  in ('CT','SL') 
    and t2.RS_OVERRIDE = 0
    and Application_review <> 'Rejected' and Application_status <> 'Rejected'))
    
 --  AND contractor_Id in ('36141')
  )
  LOOP
    Loc_Application_Id:=I.Application_Id;
    loc_mailstatus:=0;
    Loc_Applicant_Email:=null;
    LOC_APPLICATION_TYPE:=null;
    
    dbms_output.put_line(Loc_Application_Id);
    
   BEGIN 
    
     dbms_output.put_line(Loc_Application_Id|| 'check 1');
     
    SELECT  decode(application_review,'Rejected','D','RequestInfo','R','D')
    INTO loc_application_type
    from mdrp_contractor_profile 
    where contractor_id=Loc_Application_Id;
    
    select  count(*) into v_count from MDRP_CONTRACTOR_PROFILE t1  inner  join  trrp_rebate_status t2  on 
    (t1.contractor_Id =  t2.application_id)  
    where  t2.R_Reject_statuscode  in ('CT','SL') 
    and t2.RS_OVERRIDE  = 0 
    and Application_review <> 'Rejected' and Application_status <> 'Rejected'
    and contractor_id =  Loc_Application_Id;
    
    if v_count >  0  then 
    loc_application_type := 'R';
    End If  ;  
    
    
    
    
    
    
     dbms_output.put_line(Loc_Application_Id || 'check 2');
     dbms_output.put_line(LOC_APPLICATION_TYPE || 'check 2');
  
      -- ## Check the Notification if Email or Letter
    
    SELECT  count(Primary_contact_email)
    into Loc_Applicant_Email 
    from mdrp_contractor_profile 
    where contractor_id=Loc_Application_Id;
    
     IF Loc_Applicant_Email <>'0' then
     loc_mail_type := 'E';
     
     SELECT  Primary_contact_email
     into Loc_Applicant_Email 
     from mdrp_contractor_profile 
     where contractor_id=Loc_Application_Id;
     
     else
     loc_mail_type :='L';     
     end if;
  
    DBMS_OUTPUT.PUT_LINE(Loc_Application_Id || 'CHECK 1');
        
      INSERT
      INTO TEMP_REBATE_NOTIFICATION
        (
          APPLICATION_ID,
          NOTIFICATION_TYPE,
          MAILING_TYPE
        )
        VALUES
        (
          i.APPLICATION_ID,
          loc_application_type,
          loc_mail_type
        );
      COMMIT;
      
      --Replace Header Merge Codes.
      SELECT REPLACE (email_header,'[[Mail Add. Street Address]]',
      (select mailing_address from mdrp_contractor_profile 
          where contractor_id=Loc_Application_Id 
      ) )
      INTO loc_email_header
      FROM mdrp_email_template
      WHERE email_type=loc_application_type;
      
      dbms_output.put_line('Check 3');
      
      IF loc_mail_type = 'L' THEN
      SELECT REPLACE (loc_email_header,'[[ Program Promotion Image ]]','/var/www/html/swg/images/logo.png' )
      INTO loc_email_header
      FROM dual;
      else
      SELECT REPLACE (loc_email_header,'[[ Program Promotion Image ]]', 'https://swgasreferral.com/images/logo.png' )
      INTO loc_email_header
      FROM dual;
      END IF;
      
      SELECT REPLACE (loc_email_header,'[[NOTIF_DATE]]',
        (SELECT sysdate FROM dual))
      INTO loc_email_header
      FROM dual;      
      SELECT REPLACE (loc_email_header,'[[Mail Add. City]]',
        (SELECT ML_CITY
        FROM mdrp_contractor_profile 
        WHERE contractor_id=Loc_Application_Id
          )
        )
      INTO loc_email_header
      from dual;
      
      SELECT REPLACE (loc_email_header,'[[Mail Add. State]]',
        (SELECT ML_STATE
        FROM mdrp_contractor_profile 
        WHERE contractor_id=Loc_Application_Id
          )
        )
      INTO loc_email_header
      FROM dual;
      SELECT REPLACE (loc_email_header,'[[Mail Add. ZipCode]]',
        (SELECT ML_ZIP
        FROM mdrp_contractor_profile 
        WHERE contractor_id=Loc_Application_Id
          )
        )
      INTO loc_email_header
      FROM dual;    
     
        SELECT REPLACE (loc_email_header,'[[Contractor Name]]',
        (SELECT process_9002.crop_slash(nvl(Primary_contact_name,' '))
        FROM Mdrp_contractor_profile
        WHERE contractor_id=Loc_Application_Id
        ))
      INTO loc_email_header
      FROM dual;
      
        
      
      dbms_output.put_line('Check 7');
     
      loc_new_code_count:=0;
      loc_old_code_count:=0;
      compare_code:=0;
     
     FOR J IN
      (SELECT DISTINCT r_reject_statuscode
      FROM trrp_rebate_status
      WHERE application_id        =Loc_Application_Id
      AND RS_OVERRIDE != 1 order by r_reject_statuscode
      )
      loop
      Loc_Reject_Code          := J.R_Reject_Statuscode||','||Loc_Reject_Code;
      
      dbms_output.put_line(Loc_Reject_Code);
      
        begin
            SELECT DISTINCT r_custdesc
            INTO loc_custdesc
            FROM Mdrp_Reject_Statuscodes
            WHERE R_Reject_Statuscode = J.R_Reject_Statuscode;
            
      
      dbms_output.put_line('check 8');
      
            
         /* IF  J.R_Reject_Statuscode = 'AP' or  J.R_Reject_Statuscode = 'DA' THEN 
          NULL;
          Else */
            Loc_Custdesc             := '* '||Loc_Custdesc;
            temp_custdesc            := loc_custdesc||'<br><br>'||temp_custdesc;
         -- ENd IF;   
        exception WHEN no_data_found THEN
        Null;
        Dbms_Output.Put_Line('application_id' || Loc_Application_Id );
        When Others Then
        Dbms_Output.Put_Line('application_id' || Loc_Application_Id);
        END;
    END loop;
    
   dbms_output.put_line('content is' || loc_reject_code );
    dbms_output.put_line('check 9');
    
            
      IF loc_reject_code IS NULL THEN CONTINUE; END IF;
      
      DBMS_OUTPUT.PUT_LINE('check 10');
      SELECT count(reject_codes) INTO loc_app_check 
      FROM trrp_rebate_notifications 
      WHERE application_id=loc_application_id 
      AND is_active=1;
      
            IF loc_app_check >= 1 THEN
              SELECT reject_codes INTO temp_reject_code 
              FROM trrp_rebate_notifications 
              WHERE application_id=loc_application_id 
              AND is_active=1 and notification_date in 
              (select max(notification_date) from trrp_rebate_notifications where application_id=loc_application_id) ;
              
              SELECT REGEXP_COUNT(temp_reject_code,',') into loc_old_code_count  FROM DUAL;              
              SELECT REGEXP_COUNT(temp_reject_code,REPLACE(rtrim(loc_reject_code,','),',','|')) into compare_code              
              FROM DUAL;
              
              
                    If Temp_Reject_Code = Loc_Reject_Code or 
                     (compare_code=loc_new_code_count and loc_old_code_count =loc_new_code_count) Then
          --     DBMS_OUTPUT.PUT_LINE( temp_reject_code||'-'||loc_reject_code||'-'||Loc_Application_Id ); 
                        Loc_Email_Content:='';
                        Loc_reject_code:='';
                        Loc_appliance_type:='';
                        Temp_Custdesc:='';
                     
                        
                    CONTINUE;
                    END IF;
            END IF;

    
    dbms_output.put_line('check 11');
    
    /*  SELECT REPLACE (email_body,'[[Contractor Name]]',
        (SELECT process_9002.crop_slash(nvl(Primary_contact_name,' '))
        FROM Mdrp_contractor_profile
        WHERE contractor_id=Loc_Application_Id
        ))
      INTO loc_email_body
      FROM dual; */
      
      SELECT REPLACE (email_body,'[[Reject Code Description]]',temp_custdesc)
      INTO loc_email_body
      FROM MDRP_EMAIL_TEMPLATE
      WHERE email_type=loc_application_type; 
      
      
    
    SELECT REPLACE (loc_email_body,'[[Contractor Name]]',
        (SELECT process_9002.crop_slash(nvl(Primary_contact_name,' '))
        FROM Mdrp_contractor_profile
        WHERE contractor_id=Loc_Application_Id
        ))
      INTO loc_email_body
      FROM dual; 
    
    
      SELECT REPLACE (loc_email_body,'[[Timeframe]]',
        (SELECT SYSTIMESTAMP +30 FROM dual))
      INTO loc_email_body
      FROM dual;
      
      SELECT REPLACE (loc_email_body,'[[Enrollment Portal]]', '<a href="https://swgasreferral.com//">Enrollment Portal</a>' )
      INTO loc_email_body
      FROM dual;
      
      SELECT REPLACE (loc_email_body,'[[Program Terms and Conditions]]','<a href="https://swgasreferral.com/terms-conditions.php">Program Terms and Condition.</a>')
      INTO loc_email_body
      FROM dual;
    
      SELECT REPLACE (loc_email_body,'[[Program Participation Checklist]]','<a href="https://swgasreferral.com/checklist.php">Program Participation Checklist</a>')
      INTO loc_email_body
      FROM dual;
      
      
      
      
      
      
     
     
     
      /*
      if (loc_application_type='D') then
      SELECT REPLACE (loc_email_body,'[[REQINFO_DEADLINE + 30 Days]]',
        (SELECT SYSTIMESTAMP +30 FROM dual))
      INTO loc_email_body
      FROM dual;
     ELSE
      
      Select Replace (Loc_Email_Body,'[[REQINFO_DEADLINE + 30 Days]]',
        (SELECT SYSTIMESTAMP +60 FROM dual))
      INTO loc_email_body
      FROM dual;
     end if; */

     dbms_output.put_line('check 12');

   
      -- Replace Footer Merge Codes.
   
      SELECT REPLACE (email_footer,'[[Program Name]]',
        (SELECT C_FORMALCONTRACTNAME
        FROM MDRP_CONTRACTS
        WHERE C_CONTRACTNO=
          (SELECT C_CONTRACTNO FROM trrp_rebates WHERE application_id=Loc_Application_Id
          )
        ))
      INTO loc_email_footer
      FROM MDRP_EMAIL_TEMPLATE
      WHERE email_type=loc_application_type;
    
   --Concatenate and Prepare HTML Email Content.
      SELECT loc_email_footer
        ||''
        ||loc_email_content
      INTO loc_email_content
      FROM dual;
      SELECT loc_email_body
        ||''
        ||loc_email_content
      INTO loc_email_content
      FROM dual;
      SELECT loc_email_header
        ||''
        ||loc_email_content
      INTO loc_email_content
      FROM dual;
      
      
      INSERT
      INTO trrp_rebate_notifications
        (
          APPLICATION_ID,
          MAILING_ADDRESS,
          MAIL_CONTENT,
          MAILING_TYPE,
          NOTIFICATION_DATE,
          mail_status,
          reject_codes,
          is_active,
          Notification_type
        )
        VALUES
        (
          Loc_Application_Id,
          loc_applicant_email,
          loc_email_content,
          loc_mail_type,
          Systimestamp,
          loc_mailstatus,
          (select distinct loc_reject_code from dual),
          1,
          loc_application_type
        );
        
           dbms_output.put_line('check 13');
      COMMIT;
      Loc_Email_Content:='';
      Loc_reject_code:='';
      Loc_appliance_type:='';
      temp_custdesc:='';
      
    Temp_Custdesc:='';
 Exception
 When No_Data_Found Then
 Dbms_Output.Put_Line('application_id' || Loc_Application_Id );
 When Others Then
 Dbms_Output.Put_Line('application_id' || Loc_Application_Id);
 end;
  end loop;
 
END rebate_notifications;

--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
PROCEDURE CERT_EXPIRATION_REMINDERS (P_DAYS NUMBER)
AS
  loc_app_check        NUMBER;
  loc_contractor_id   NUMBER;
  loc_application_type VARCHAR2(2);
  loc_applicant_email TRRP_REBATES.R_APPLICANTEMAIL%TYPE;
   loc_contractor_email TRRP_REBATES.R_APPLICANTEMAIL%TYPE;
  loc_mail_type VARCHAR2(1 CHAR);
  loc_email_content CLOB:=NULL;
  loc_email_header VARCHAR2(4000 CHAR);
  loc_email_body   VARCHAR2(4000 CHAR);
  loc_email_footer VARCHAR2(4000 CHAR);
  loc_custdesc     VARCHAR2(4000 CHAR);
  Temp_Custdesc    VARCHAR2(4000 CHAR):=NULL;
  loc_reject_code  VARCHAR2(1000)     :=NULL;
  temp_reject_code  VARCHAR2(1000);
  loc_appliance_type  VARCHAR2(1000)  :=NULL;
  temp_appliance_type  varchar2(1000) :=NULL;
  loc_contract			VARCHAR2(100);
  loc_payee   number(6);
  landfname varchar2(60);
  landlname varchar2(60);
  last_notif_date    trrp_rebate_notifications.notification_date%type;
  Date_Diff Number;
  Loc_Reccount Number;
  loc_mailstatus number(1);
   loc_agency  varchar(50); 
BEGIN
  --EXECUTE IMMEDIATE 'truncate table temp_rebate_notification';
  FOR i IN
  (   
      SELECT APPLICATION_ID, WM_CONCAT(DOCUMENTS) DOCUMENTS FROM (
      SELECT  APPLICATION_ID, to_char(doc_id) as documents 
      FROM TRRP_REBATE_DOCS 
      WHERE DELETED=0 
      AND DOCUMENT_TYPE IN ('1','2','3') and DOC_STATUS = 'A'
      AND POLICY_EXPIRE_DATE  <= to_date(SYSDATE + P_DAYS) 
	  AND (TO_DATE(SYSDATE + 60)-POLICY_EXPIRE_DATE)<=30 --Added By Mohit
      AND POLICY_EXPIRE_DATE is NOT NULL       
      UNION
      SELECT CONTRACTOR_ID, to_char(license_type) as documents
      FROM TRRP_CONTRACTOR_INPUTS
      WHERE LICENSE_TYPE IN ('ML','SL','CT') AND DOC_STATUS='A'
      AND EXPIRATION_DATE <= to_date(SYSDATE + P_Days)
	  AND (TO_DATE(SYSDATE + 60)-EXPIRATION_DATE)<=30 --Added By Mohit
      and EXPIRATION_DATE IS NOT NULL      
      )
      WHERE  APPLICATION_ID IN  
     (SELECT CONTRACTOR_ID FROM MDRP_CONTRACTOR_PROFILE
     WHERE ((APPLICATION_REVIEW='Approved' and APPLICATION_STATUS='Approved') or 
     (application_review='Rejected' and application_status='Rejected' and application_reject_reason='3'))
     /* and doc_id not in (select nvl(doc_id,0) from trrp_rebate_notifications)*/ )
   GROUP BY APPLICATION_ID
    )
    LOOP
    Loc_contractor_Id:=I.Application_Id;
    Loc_Email_Content:='';
    loc_mailstatus:=0;
    loc_mail_type      := 'E';
    loc_application_type :='C';  
    Loc_reject_code:='';
    Loc_appliance_type:='';
    temp_custdesc:='';
    Loc_Custdesc  :=null;
   
    dbms_output.put_line(Loc_contractor_Id);
    
   BEGIN 
    
          -- ## Check the Notification if Email or Letter
    
    SELECT  count(Primary_contact_email)
    into Loc_Applicant_Email 
    from mdrp_contractor_profile 
    where contractor_id=Loc_contractor_Id;
    
     IF Loc_Applicant_Email <>'0' then
     loc_mail_type := 'E';
     
     SELECT  Primary_contact_email
     into Loc_Applicant_Email 
     from mdrp_contractor_profile 
     where contractor_id=Loc_contractor_Id;
     
     else
     loc_mail_type :='L';     
     end if;
    
    dbms_output.put_line('Check 1');
 
      SELECT REPLACE (email_header,'[[Mail Add. Street Address]]',
      (select business_address  from mdrp_contractor_profile
          where contractor_id=Loc_contractor_Id ) )
      INTO loc_email_header
      FROM mdrp_email_template
      WHERE email_type=loc_application_type;
      
     
      IF loc_mail_type = 'L' THEN
      SELECT REPLACE (loc_email_header,'[[ Program Promotion Image ]]','/var/www/html/swg/images/logo.png' )
      INTO loc_email_header
      FROM dual;
      else
      SELECT REPLACE (loc_email_header,'[[ Program Promotion Image ]]', 'https://swgasreferral.com/images/logo.png' )
      INTO loc_email_header
      FROM dual;
      END IF;

      SELECT REPLACE (loc_email_header,'[[NOTIF_DATE]]',
        (SELECT sysdate FROM dual))
      INTO loc_email_header
      FROM dual;
      
      SELECT REPLACE (loc_email_header,'[[Mail Add. City]]',
        (select city  from mdrp_contractor_profile
        where contractor_id=Loc_contractor_Id ))
      INTO loc_email_header
      from dual;
    
      SELECT REPLACE (loc_email_header,'[[Mail Add. State]]',
        (select state  from mdrp_contractor_profile
        where contractor_id=Loc_contractor_Id ))
      INTO loc_email_header
      FROM dual;
      
      SELECT REPLACE (loc_email_header,'[[Mail Add. ZipCode]]',
        (select zip  from mdrp_contractor_profile
        where contractor_id=Loc_contractor_Id))
      INTO loc_email_header
      FROM dual;    
    	 
     SELECT REPLACE (loc_email_header,'[[Contractor Name]]',
     (SELECT process_9002.crop_slash(nvl(company_name,' '))
      from mdrp_contractor_profile
      where contractor_id=Loc_contractor_Id ))
      INTO loc_email_header
      FROM dual;
 
            
      select replace (loc_email_header,'[[Contact Name]]',
      (select primary_contact_name from mdrp_contractor_profile where contractor_id=Loc_contractor_Id
      ))into loc_email_header    from dual;    
      
       SELECT REPLACE (loc_email_header,'[[Enrollment Portal]]', '<a href="https://swgasreferral.com/">Enrollment Portal</a>' )
      INTO loc_email_header
      FROM dual;
     
     SELECT REPLACE (loc_email_header,'[[Referral Program Directory]]','<a href="https://swgasreferral.com/contractor-listing.php/">Referral Program Directory</a>')
      INTO loc_email_header
      FROM dual;
   dbms_output.put_line('Check 2');
    
    For j in (select application_id, document_type, doc_status, policy_expire_date,'' state,''city
              from trrp_rebate_docs where 
              policy_expire_date is not null 
              and deleted=0 
              and application_id=loc_contractor_id 
              and doc_status = 'A'
              and policy_expire_date  < to_date(sysdate + p_days)
			  AND (TO_DATE(SYSDATE + 60)-POLICY_EXPIRE_DATE)<=30 --Added By Mohit
              union
              select contractor_id, license_type as document_type, doc_status, expiration_date as policy_expire_date, 
              decode(cb_state,'AZ','Arizona','NV','Nevada','CA','California') state, 
              (select checkbx_tier2 from mdrp_form_checkboxes  where cb_id=contractor_map_cb_id and isactive=1) city
              from trrp_contractor_inputs 
              where license_type is not null 
              and expiration_date is not null
              and contractor_id=loc_contractor_id
              and doc_status = 'A'
              and expiration_date < to_date(sysdate + p_days)
			   AND (TO_DATE(SYSDATE + 60)-expiration_date)<=30 --Added By Mohit
              order by document_type)
    loop    
    
    select decode(j.document_type, '1','Workers Compensation','2','Automobile Insurance','3','General Liability Insurance',
                     'ML','Manufacturing License','SL','Contract/State License','CT','City License')
    into Loc_Custdesc from dual;   
    
    
    Loc_Reject_Code          := J.document_type||','||Loc_Reject_Code;
    If (j.document_type in ('1','2','3')) then
    Loc_Custdesc             := '* '||Loc_Custdesc||' -  '||to_char(j.policy_expire_date,'mm/dd/yyyy');    
    Elsif (j.document_type in ('ML','SL')) then
    Loc_Custdesc             := '* '||Loc_Custdesc||' -  '||j.state||' -  '||to_char(j.policy_expire_date,'mm/dd/yyyy');
    Elsif j.document_type='CT' then
    Loc_Custdesc             := '* '||Loc_Custdesc||' -  '||j.city||' -  '||to_char(j.policy_expire_date,'mm/dd/yyyy');
    End If;
    temp_custdesc            := loc_custdesc||'<br><br>'||temp_custdesc; 
    end loop;
     
            
    IF temp_custdesc IS NULL THEN CONTINUE;   END IF;
    
    
     SELECT count(reject_codes) INTO loc_app_check 
      FROM trrp_rebate_notifications 
      WHERE application_id=loc_contractor_id  and notification_type='C'
      AND is_active=1;
      
            IF loc_app_check >= 1 THEN
              SELECT reject_codes INTO temp_reject_code 
              FROM trrp_rebate_notifications 
              WHERE application_id=loc_contractor_id and notification_type='C'
              AND is_active=1 and notification_date in 
              (select max(notification_date) from trrp_rebate_notifications where application_id=loc_contractor_id) ;
              
                    If Temp_Reject_Code = Loc_Reject_Code Then
                        Loc_Email_Content:='';
                        Loc_reject_code:='';
                        Loc_appliance_type:='';
                        Temp_Custdesc:='';                   
                        
                          CONTINUE;
                    END IF;    
     END IF;
      
      
      dbms_output.put_line('Check 4');
      

      SELECT REPLACE (loc_email_header,'[[Document Type]]',temp_custdesc)      
      INTO loc_email_header
      FROM dual;
      
      
      dbms_output.put_line('Check5'||loc_email_header);
      
      SELECT loc_email_header
        ||''
        ||loc_email_content
      INTO loc_email_content
      FROM dual;
      
      dbms_output.put_line('Check6'||loc_email_content || i.documents );
      
      INSERT
      INTO trrp_rebate_notifications
        (
          APPLICATION_ID,
          MAILING_ADDRESS,
          MAIL_CONTENT,
          MAILING_TYPE,
          NOTIFICATION_DATE,
          mail_status,
          reject_codes,
          is_active,
          notification_type
          --DOC_id
        )
        VALUES
        (
          Loc_Contractor_Id,
          loc_applicant_email,
          loc_email_content,
          loc_mail_type,
          Systimestamp,
          loc_mailstatus,
          (select distinct loc_reject_code from dual),
          1,
          'C'
          --i.documents
        );
      COMMIT;
    
      
 Exception
 When No_Data_Found Then
 Dbms_Output.Put_Line('application_id' || Loc_Contractor_Id );
 When Others Then
 Dbms_Output.Put_Line('application_id' || Loc_Contractor_Id);
 end;
  end loop;
 
END CERT_EXPIRATION_REMINDERS;

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
PROCEDURE INCOMPLETE_APPS_EXPIRATION (P_DAYS NUMBER)
AS
  loc_app_check        NUMBER;
  loc_contractor_id   NUMBER;
  loc_application_type VARCHAR2(2);
  loc_applicant_email TRRP_REBATES.R_APPLICANTEMAIL%TYPE;
   loc_contractor_email TRRP_REBATES.R_APPLICANTEMAIL%TYPE;
  loc_mail_type VARCHAR2(1 CHAR);
  loc_email_content CLOB:=NULL;
  loc_email_header VARCHAR2(4000 CHAR);
  loc_email_body   VARCHAR2(4000 CHAR);
  loc_email_footer VARCHAR2(4000 CHAR);
  loc_custdesc     VARCHAR2(4000 CHAR);
  Temp_Custdesc    VARCHAR2(4000 CHAR):=NULL;
  loc_reject_code  VARCHAR2(1000)     :=NULL;
  temp_reject_code  VARCHAR2(1000);
  loc_appliance_type  VARCHAR2(1000)  :=NULL;
  temp_appliance_type  varchar2(1000) :=NULL;
  loc_contract			VARCHAR2(100);
  loc_payee   number(6);
  landfname varchar2(60);
  landlname varchar2(60);
  last_notif_date    trrp_rebate_notifications.notification_date%type;
  Date_Diff Number;
  Loc_Reccount Number;
  loc_mailstatus number(1);
   loc_agency  varchar(50); 
   v_results number;
  v_reviewstatus varchar2(50);
  v_status varchar2(50);
  v_listing varchar2(2);

BEGIN
  --EXECUTE IMMEDIATE 'truncate table temp_rebate_notification';
  FOR i IN
  (select contractor_id from (
   select contractor_id from mdrp_contractor_profile where sysdate - trunc(createdon) > p_days and 
   application_review in ('Hold') and application_status not in('Approved','Rejected') and APP_SUBMITTED <> 1 
   union 
   select contractor_id from mdrp_contractor_profile t1
   Inner Join (Select Max(Trunc(Notification_Date)) Last_Notif, Application_Id From Trrp_Rebate_Notifications where notification_type='R' Group By Application_Id) T3
   On (T1.contractor_Id=T3.Application_Id)
   where t1.application_review in ('Request Info') and t1.application_status not in('Approved','Rejected') )   
   where contractor_id not in (select application_id from trrp_rebate_notifications where notification_type='E')
  -- and contractor_id=33905
    )
    LOOP
    Loc_contractor_Id:=i.contractor_id;
    Loc_Email_Content:='';
    loc_mailstatus:=0;
    loc_mail_type      := 'E';
    loc_application_type :='E';  
    Loc_reject_code:='';
    Loc_appliance_type:='';
    temp_custdesc:='';
    Loc_Custdesc  :=null;
    v_reviewstatus:=NULL;
    v_status:=NULL;
    v_listing:=NULL;
   
    dbms_output.put_line(Loc_contractor_Id);
    
   BEGIN 
    
    Select application_review,application_status,website_listing_option,Primary_Contact_Email 
    Into V_Reviewstatus,V_Status,V_Listing,Loc_Applicant_Email
    From mdrp_contractor_profile where contractor_id =Loc_contractor_Id; 
    
  -- Set the Status for thr Dealer to Rejected.  
    
  UPDATE MDRP_CONTRACTOR_PROFILE SET 
   APPLICATION_REVIEW='Rejected',
   APPLICATION_STATUS='Rejected',
   MODIFIEDON=SYSTIMESTAMP,
   MODIFIEDBY='SYSTEM',
   WEBSITE_LISTING_OPTION=0
   WHERE CONTRACTOR_ID=Loc_contractor_Id;
   
   -- Add comments about the expiration for the time frame to submit the application
   
   V_RESULTS:= PROCESS_6006.INSERT_CONTRACTOR_REMARKS(Loc_contractor_Id,'Expired as your application was not completed within the timeframe required','34842',V_REVIEWSTATUS,V_STATUS,'Rejected','Rejected',V_LISTING,0 );
    
  -- Make Changes to template  
    dbms_output.put_line('Check 1');
 
      SELECT REPLACE (email_header,'[[Mail Add. Street Address]]',
      (select business_address  from mdrp_contractor_profile
          where contractor_id=Loc_contractor_Id ) )
      INTO loc_email_header
      FROM mdrp_email_template
      WHERE email_type=loc_application_type;
      
     
      SELECT REPLACE (loc_email_header,'[[ Program Promotion Image ]]', 'https://swg.conservationrebates.com/images/logo.png' )
      INTO loc_email_header
      FROM dual;

      SELECT REPLACE (loc_email_header,'[[NOTIF_DATE]]',
        (SELECT sysdate FROM dual))
      INTO loc_email_header
      FROM dual;
      
      SELECT REPLACE (loc_email_header,'[[Mail Add. City]]',
        (select city  from mdrp_contractor_profile
        where contractor_id=Loc_contractor_Id ))
      INTO loc_email_header
      from dual;
    
      SELECT REPLACE (loc_email_header,'[[Mail Add. State]]',
        (select state  from mdrp_contractor_profile
        where contractor_id=Loc_contractor_Id ))
      INTO loc_email_header
      FROM dual;
      
      SELECT REPLACE (loc_email_header,'[[Mail Add. ZipCode]]',
        (select zip  from mdrp_contractor_profile
        where contractor_id=Loc_contractor_Id))
      INTO loc_email_header
      FROM dual;    
    	 
     SELECT REPLACE (loc_email_header,'[[Contractor Name]]',
     (SELECT process_9002.crop_slash(nvl(company_name,' '))
      from mdrp_contractor_profile
      where contractor_id=Loc_contractor_Id ))
      INTO loc_email_header
      FROM dual;
 
            
      select replace (loc_email_header,'[[Contact Name]]',
      (select primary_contact_name from mdrp_contractor_profile where contractor_id=Loc_contractor_Id
      ))into loc_email_header    from dual;    
      
      SELECT REPLACE (loc_email_header,'[[Enrollment Portal]]', '<a href="https://swg.conservationrebates.com/">Enrollment Portal</a>' )
      INTO loc_email_header
      FROM dual;
      
      SELECT REPLACE (loc_email_header,'[[Program Terms and Conditions]]','<a href="https://swg.conservationrebates.com/">Program Terms and Condition.</a>')
      INTO loc_email_header
      FROM dual;
    
      SELECT REPLACE (loc_email_header,'[[Program Participation Checklist]]','<a href="https://swg.conservationrebates.com/">Program Participation Checklist</a>')
      INTO loc_email_header
      FROM dual;  
    
     
    dbms_output.put_line('Check 3'||temp_custdesc); 
            
   /* IF temp_custdesc IS NULL THEN CONTINUE;   END IF;
    
    
     SELECT count(reject_codes) INTO loc_app_check 
      FROM trrp_rebate_notifications 
      WHERE application_id=loc_contractor_id  and notification_type='C'
      AND is_active=1;
      
            IF loc_app_check >= 1 THEN
              SELECT reject_codes INTO temp_reject_code 
              FROM trrp_rebate_notifications 
              WHERE application_id=loc_contractor_id and notification_type='C'
              AND is_active=1 and notification_date in 
              (select max(notification_date) from trrp_rebate_notifications where application_id=loc_contractor_id) ;
              
                    If Temp_Reject_Code = Loc_Reject_Code Then
                        Loc_Email_Content:='';
                        Loc_reject_code:='';
                        Loc_appliance_type:='';
                        Temp_Custdesc:='';                   
                        
                          CONTINUE;
                    END IF;    
     END IF;*/
      
      
      
      
      dbms_output.put_line('Check5'||loc_email_header);
      
      SELECT loc_email_header
        ||''
        ||loc_email_content
      INTO loc_email_content
      FROM dual;
      
      dbms_output.put_line('Check6'||loc_email_content);
      
      INSERT
      INTO trrp_rebate_notifications
        (
          APPLICATION_ID,
          MAILING_ADDRESS,
          MAIL_CONTENT,
          MAILING_TYPE,
          NOTIFICATION_DATE,
          mail_status,
          reject_codes,
          is_active,
          notification_type
        )
        VALUES
        (
          Loc_Contractor_Id,
          loc_applicant_email,
          loc_email_content,
          loc_mail_type,
          Systimestamp,
          loc_mailstatus,
          (select distinct loc_reject_code from dual),
          1,
          loc_application_type
        );
      COMMIT;
    
      
 Exception
 When No_Data_Found Then
 Dbms_Output.Put_Line('application_id' || Loc_Contractor_Id );
 When Others Then
 Dbms_Output.Put_Line('application_id' || Loc_Contractor_Id);
 end;
  end loop;
 
END INCOMPLETE_APPS_EXPIRATION ;
--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
END PROCESS_4004;