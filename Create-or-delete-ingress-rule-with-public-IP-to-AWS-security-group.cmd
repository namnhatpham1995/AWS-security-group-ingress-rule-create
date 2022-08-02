@echo off
:: set all the variables in this script locally to make sure they are cleared after finishing
setlocal

set SECURITY_GROUP_ID=sg-06c04c10fc3a5cdb4

for /F %%I in ('curl -ssS https://checkip.amazonaws.com') do set CURRENT_PUBLIC_IP=%%I

for /F %%I in ('aws iam get-user --output text --query "User.UserName"') do set AWS_USERNAME=%%I 
set "SG_DESCRIPTION=%AWS_USERNAME%-dev-machine"
:: remove space between words
set SG_DESCRIPTION=%SG_DESCRIPTION: =%

:: Check old public ip address
for /F %%I in ('aws ec2 describe-security-groups --filters "Name=group-id,Values=%SECURITY_GROUP_ID%" --output text --query "SecurityGroups[*].IpPermissions[*].IpRanges[?Description=='%SG_DESCRIPTION%'].CidrIp"') do set OLD_PUBLIC_IP=%%I
IF not "%OLD_PUBLIC_IP%"=="" (
	call :DELETE_OLD_INGRESS_RULE
)
:: Option arguments check
set argument_count=0
for %%x in (%*) do Set /A argument_count+=1
if %argument_count% GTR 0 (
	:: End the script if there is argument -d or --delete
	for %%x in (%*) do (
		IF %%~x == -d (
		:: End the script
			goto :EOF
		)
		IF %%~x == --delete (
		:: End the script
			goto :EOF
		)	
	)
)

call :CREATE_NEW_INGRESS_RULE

endlocal

:: End the script
goto :EOF


:: FUNCTIONS

:EOF
	EXIT /B
	
:CREATE_NEW_INGRESS_RULE
	aws ec2 authorize-security-group-ingress 	^
	--group-id %SECURITY_GROUP_ID% 				^
	--ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=%CURRENT_PUBLIC_IP%/32,Description=%SG_DESCRIPTION%}]"
	EXIT /B 0 	:: End the function

:DELETE_OLD_INGRESS_RULE
	aws ec2 revoke-security-group-ingress 	^
		--group-id %SECURITY_GROUP_ID% 		^
		--protocol tcp 						^
		--port 22							^
		--cidr %OLD_PUBLIC_IP%
	EXIT /B 0	:: End the function