@echo off

:: set all the variables in this script locally to make sure they are cleared after finishing
setlocal enabledelayedexpansion

set argumentCount=0
set acceptedArguments=0
:: Option arguments check
if not [%1]==[] (
	:: End the script if there is argument -d or --delete
	for %%x in (%*) do (
		set /A argumentCount+=1
		IF %%~x == -d (
			set "DELETE_MODE=true"
			set /A acceptedArguments+=1
		)
		IF %%~x == --delete (
			set "DELETE_MODE=true"
			set /A acceptedArguments+=1
		)
		IF %%~x == --help (
			goto :HELP
		)
		IF %%~x == -h (
			goto :HELP
		)
	)
	IF not [!argumentCount!] == [!acceptedArguments!] (
		echo.
		echo Wrong options choice, read help message to get more information
		goto :HELP
	) 
)

set SECURITY_GROUP_ID=sg-06c04c10fc3a5cdb4

:: Set CURRENT_PUBLIC_IP variable
for /F %%I in ('curl -ssS https://checkip.amazonaws.com') do set CURRENT_PUBLIC_IP=%%I

:: Set AWS_USERNAME variable
for /F %%I in ('aws iam get-user --output text --query "User.UserName"') do set AWS_USERNAME=%%I 
set "SG_DESCRIPTION=%AWS_USERNAME%-dev-machine"
:: remove space between words
set SG_DESCRIPTION=%SG_DESCRIPTION: =%

:: Check old public ip address
for /F %%I in ('aws ec2 describe-security-groups --filters "Name=group-id,Values=%SECURITY_GROUP_ID%" --output text --query "SecurityGroups[*].IpPermissions[*].IpRanges[?Description=='%SG_DESCRIPTION%'].CidrIp"') do set OLD_PUBLIC_IP=%%I
IF not "%OLD_PUBLIC_IP%"=="" (
	call :DELETE_OLD_INGRESS_RULE
)

if "%DELETE_MODE%" == "true" (
    goto :EOF
)

call :CREATE_NEW_INGRESS_RULE

endlocal

:: End the script
goto :EOF


:: FUNCTIONS

:EOF
	EXIT /B
	
:CREATE_NEW_INGRESS_RULE
	aws ec2 authorize-security-group-ingress 		^
		--group-id %SECURITY_GROUP_ID% 				^
		--ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=%CURRENT_PUBLIC_IP%/32,Description=%SG_DESCRIPTION%}]" >nul
	EXIT /B 0 	:: End the function

:DELETE_OLD_INGRESS_RULE
	aws ec2 revoke-security-group-ingress 	^
		--group-id %SECURITY_GROUP_ID% 		^
		--protocol tcp 						^
		--port 22							^
		--cidr %OLD_PUBLIC_IP% >nul
	EXIT /B 0	:: End the function

:HELP
	echo.
	echo ----------HELP MESSAGE----------
	echo This script is used to clear OLD ingress rules (containing old IP address(es))
	echo and add the NEW  ingress rule(s) (containing new IP address(es))
	echo to a determined AWS security group.
	echo.
	echo ^+^+^+ATTENTION^+^+^+:
	echo Before running the script please check that you are using the correct security group id.
	echo If not please adapt the variable SECURITY_GROUP_ID inside the script accordingly.
	echo For PI1 team's resources, the default security group is ^*^*^*sg-06c04c10fc3a5cdb4^*^*^* .
	echo.
	echo Syntax: PI1-team-set-ingress-rule-with-public-IP-to-AWS-security-group.cmd [OPTIONS]
	echo.
	echo OPTIONS:
	echo -h ^| --help             get list of commands
	echo -d ^| --delete           only delete the old ingress rule without adding new one
	echo.
	EXIT /B