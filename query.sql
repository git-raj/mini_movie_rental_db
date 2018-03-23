select * from Membership_info

ALTER TABLE MEMBERSHIP_INFO
ADD MONTHLY_DVD_ISSUED_COUNT NUMBER;

INSERT INTO MEMBERSHIP_INFO(MONTHLY_DVD_ISSUED_COUNT)
VALUES (0);

UPDATE MEMBERSHIP_INFO
SET MONTHLY_DVD_ISSUED_COUNT=0
WHERE MONTHLY_DVD_ISSUED_COUNT IS NULL;

------------

CREATE OR REPLACE PROCEDURE PROC_RENTAL(MEM_ID IN NUMBER, MOV_ID IN NUMBER, RENTED_DT IN DATE)

AS

CURR_ME DATE;

BEGIN

/*
procedure to update membership info and movie inventory
HISTORY:
Created by Saroj on 11/16/2016
Updated by:
Saroj, added month to month dvd issued calculations- 11/20/2016

*/
  --set variable with current monthend value for the member
  SELECT M.CURRENT_MONTHEND INTO CURR_ME FROM MEMBERSHIP_INFO M WHERE M.MEMBER_ID = MEM_ID;

  --updating movie inventory
  UPDATE MOVIE_INVENTORY I
  SET I.INVENTORY_IN_HAND = I.INVENTORY_IN_HAND - 1,
      I.INVENTORY_OUT = I.INVENTORY_OUT + 1
  WHERE I.MOVIE_ID = MOV_ID;
  
  DBMS_OUTPUT.put_line('MOVIE_INVENTORY table updated for: '||MOV_ID||'  for available inventory count and dvd issued count');
  
  --update current dvd issued count
  UPDATE MEMBERSHIP_INFO M
  SET M.CURRENT_DVD_ISSUED= (M.CURRENT_DVD_ISSUED + 1)
  WHERE M.MEMBER_ID = MEM_ID;
  
  DBMS_OUTPUT.put_line('MEMBERSHIP_INFO table for member id: '||MEM_ID ||' updated with current dvd issued count');
  
  --updating the current monthend for new members getting rental for the first time
   UPDATE MEMBERSHIP_INFO
   SET CURRENT_MONTHEND = LAST_DAY(RENTED_DT)
   WHERE CURRENT_MONTHEND IS NULL
   AND MEMBER_ID = MEM_ID;
   
  IF(CURR_ME < RENTED_DT) THEN
  --reseting rental count for new month
    UPDATE MEMBERSHIP_INFO
    SET MONTHLY_DVD_ISSUED_COUNT = 1
    WHERE MEMBER_ID = MEM_ID;
  
  ELSE
  --updating rental count for the month
    UPDATE MEMBERSHIP_INFO
    SET MONTHLY_DVD_ISSUED_COUNT = MONTHLY_DVD_ISSUED_COUNT+1
    WHERE MEMBER_ID = MEM_ID;  
  
  END IF;
  
  --update monthend for all scenarios after a rental
  UPDATE MEMBERSHIP_INFO L
  SET L.CURRENT_MONTHEND = LAST_DAY(RENTED_DT)
  WHERE L.MEMBER_ID = MEM_ID;

  COMMIT;
  
END;
/
-------------------

CREATE OR REPLACE PROCEDURE PROC_RENTAL_LOSS(MEM_ID IN NUMBER, MOV_ID IN NUMBER, LOSS_INDICATOR IN VARCHAR2)

AS

BEGIN

/*
procedure to update rental dvd lost
HISTORY:
Created by Saroj on 11/16/2016
Updated by:

*/
 
 --updating billing table with fine for lost dvd
 
  UPDATE BILLING M
  SET M.INCIDENTAL_FEES = (M.INCIDENTAL_FEES + 25) --hardcoded $25 fine per dvd loss
  WHERE LOSS_INDICATOR = 'Y' AND M.MEMBER_ID = MEM_ID ;
  DBMS_OUTPUT.put_line('BILLING table for member id: '||MEM_ID ||' added with $25 fine for lost DVD');
 
  -- updating inventory table to reduce the available count
  
  UPDATE MOVIE_INVENTORY I
  SET I.LOST_DVD_COUNT = (I.LOST_DVD_COUNT + 1)
  WHERE LOSS_INDICATOR= 'Y' AND I.MOVIE_ID = MOV_ID;
  DBMS_OUTPUT.put_line('MOVIE_INVENTORY table for movie id: '||MOV_ID ||' updated on lost movie count');  
  
END;
/
------------------

:::::::::::::::::::::::::
this needs more work:::::::::::::::::::::::::::::::::::
::::::::::::::::::::::

CREATE OR REPLACE TRIGGER RENTAL
AFTER INSERT OR UPDATE OF RENTAL_ID, MEMBER_ID, MOVIE_ID, RENTED_DATE ON RENTAL_INFO
FOR EACH ROW

BEGIN
/*
HISTORY:
Created by Saroj on 11/16/2016
Updated by:
Saroj, for rental history archive on 11/17/2016

*/
  --triggers the procedure, passes the parameters of new inserts
  CS699_TERM.PROC_RENTAL(:NEW.MEMBER_ID, :NEW.MOVIE_ID);
  
  --inserts records into archive/history table
  INSERT INTO RENTAL_HISTORY(RENTAL_ID, MEMBER_ID, MOVIE_ID, RENTED_DATE)
  VALUES(:NEW.RENTAL_ID, :NEW.MEMBER_ID, :NEW.MOVIE_ID, :NEW.RENTED_DATE);
  
END;


-------------------

ALTER TABLE MEMBERSHIP_INFO
ADD (CURRENT_MONTHLY_ISSUED_COUNT NUMBER,
    UPDATED_DATESTAMP DATE,
    CURRENT_MONTHEND DATE);


-----------------------------

   CREATE SEQUENCE  "CS699_TERM"."RENTAL_ID_SEQ"  
   MINVALUE 1 MAXVALUE 9999999999999999999999999999 
   INCREMENT BY 1 START WITH 1 NOCACHE  NOORDER  NOCYCLE  NOPARTITION ;


------------------------------

CREATE OR REPLACE TRIGGER QUEUE_RENTAL_TRIG
AFTER INSERT OR UPDATE OF QUEUE_ID, MEMBER_ID, MOVIE_ID ON QUEUE_TABLE
FOR EACH ROW

DECLARE

V_MEMBER_VALID_DVD_ISSUE NUMBER;

BEGIN

--SELECT COUNT(I.MEMBER_ID) INTO V_MEMBER_VALID_DVD_ISSUE FROM V_MEMBER_DVD I
--WHERE I.MEMBER_ID = :NEW.MEMBER_ID;

SELECT COUNT(I.MEMBER_ID) INTO V_MEMBER_VALID_DVD_ISSUE from MEMBERSHIP_INFO I
JOIN MEMBERSHIP_TYPE T
ON I.MEMBERSHIP_TYPE_ID = T.MEMBERSHIP_TYPE_ID
WHERE LTRIM(RTRIM(I.MEMBERSHIP_STATUS)) ='CURRENT'
AND I.MONTHLY_DVD_ISSUED_COUNT<T.MAX_DVD_ALLOWED_PER_MONTH
AND I.CURRENT_DVD_ISSUED < T.DVD_AT_A_TIME
AND I.MEMBER_ID = :NEW.MEMBER_ID;

IF(V_MEMBER_VALID_DVD_ISSUE > 0) THEN
INSERT INTO RENTAL_INFO(RENTAL_ID, MEMBER_ID, MOVIE_ID, RENTED_DATE)
VALUES(RENTAL_ID_SEQ.NEXTVAL, :NEW.MEMBER_ID, :NEW.MOVIE_ID, SYSDATE);

END IF;

END;
/

----------------------------------
decommissioned VIEW:

CREATE OR REPLACE VIEW V_MEMBER_DVD
AS
SELECT I.MEMBER_ID,I.CURRENT_DVD_ISSUED,I.MONTHLY_DVD_ISSUED_COUNT FROM MEMBERSHIP_INFO I
JOIN MEMBERSHIP_TYPE T
ON I.MEMBERSHIP_TYPE_ID = T.MEMBERSHIP_TYPE_ID
WHERE LTRIM(RTRIM(I.MEMBERSHIP_STATUS)) ='CURRENT'
AND I.MONTHLY_DVD_ISSUED_COUNT < T.MAX_DVD_ALLOWED_PER_MONTH
AND I.CURRENT_DVD_ISSUED < T.DVD_AT_A_TIME;

--------------------

CREATE OR REPLACE PROCEDURE RENTAL_RETURN_QUEUE_UPDATE(MEM_ID IN NUMBER)

AS

V_QUEUE_COUNT NUMBER;
V_QUEUE_ID NUMBER;
Q_MOV_ID NUMBER;
V_MEMBER_VALID_DVD_ISSUE NUMBER;

BEGIN

SELECT COUNT(QUEUE_ID) INTO V_QUEUE_COUNT FROM QUEUE_TABLE Q
WHERE SHIPPED_STATUS='N'
AND MEMBER_ID=MEM_ID;

SELECT MIN(QUEUE_ID) INTO V_QUEUE_ID FROM QUEUE_TABLE Q
WHERE SHIPPED_STATUS='N'
AND MEMBER_ID=MEM_ID;

SELECT MOVIE_ID INTO Q_MOV_ID FROM QUEUE_TABLE Q
WHERE SHIPPED_STATUS='N'
AND MEMBER_ID=MEM_ID
AND QUEUE_ID = V_QUEUE_ID;

SELECT COUNT(I.MEMBER_ID) INTO V_MEMBER_VALID_DVD_ISSUE from MEMBERSHIP_INFO I
JOIN MEMBERSHIP_TYPE T
ON I.MEMBERSHIP_TYPE_ID = T.MEMBERSHIP_TYPE_ID
WHERE LTRIM(RTRIM(I.MEMBERSHIP_STATUS)) ='CURRENT'
AND I.MONTHLY_DVD_ISSUED_COUNT<T.MAX_DVD_ALLOWED_PER_MONTH
AND I.CURRENT_DVD_ISSUED < T.DVD_AT_A_TIME
AND I.MEMBER_ID = MEM_ID;

IF((V_MEMBER_VALID_DVD_ISSUE > 0) AND (V_QUEUE_COUNT>0)) THEN
INSERT INTO RENTAL_INFO(RENTAL_ID, MEMBER_ID, MOVIE_ID, RENTED_DATE)
VALUES(RENTAL_ID_SEQ.NEXTVAL, MEM_ID, Q_MOV_ID, SYSDATE);

--delete the queue entry after the movie rental has been issued
DELETE FROM QUEUE_TABLE
WHERE QUEUE_ID= V_QUEUE_ID;

END IF;

END;

--------------