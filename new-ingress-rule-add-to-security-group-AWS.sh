#!/bin/bash
set +x

# creator: Nam Nhat Pham
#
# "*******************************************************************************************************************************"
#  ** This script clears OLD ingress rule (containing old IP-Adress) then adds the NEW  ingress rule (containing new IP-Adress) **
#  ** of the current computer to an AWS security group.                                                                         **
# "*******************************************************************************************************************************"
# "As per AWS Security group rule limit for IPV4 address for egress -- it is 60 rules per SG."
# "Hence it is important to remove individual's OLD ip when updating the new one"
#
# How to use the script:
# Run command with a security group id: ./script.sh -s security-group-id [-h|-c|...] [-i|-o|... [value]]
#

###################################################################################################################################################
### FUNCTIONS #####################################################################################################################################
###################################################################################################################################################

# List all the available argument options
help(){
  echo "This script is used to clear OLD ingress rules (containing old IP address(es))"
  echo "and add the NEW  ingress rule(s) (containing new IP address(es))"
  echo "to a determined AWS security group."
  echo
  echo "Syntax: ./`basename "$0"` -s <security-group-id> [option(s)]"
  echo
  echo "options without value:"
  echo "-c | --clear-rules                        clear the old security group rule(s)"
  echo "-f | --fresh-mode                         fresh mode removes any rules created by the same aws user"
  echo "-h | --help                               get list of command"
  echo "-l | --list-rules                         get list of available rules in the security group"
  echo "-v | --verbose                            set verbose mode (print all information)"
  echo "-y | --yes-mode                           yes input automatically for yes-no choice"
  echo
  echo "options with value(s):"
  echo "-i | --ip             <public-ip-address>                                set ip address to add to security group"
  echo "-p | --port           <begin-port-number> [end-port-number]              set port/port range"
  echo
}

add_new_security_group_rule(){
    if $VERBOSE; then
        echo
        echo "-----Add NEW INGRESS RULE to security group $SECURITY_GROUP_IDS in region $REGION-----"
        echo
    fi

    if $VERBOSE; then
        echo "About to add new ip to security group id $SECURITY_GROUP_IDS in region $REGION"
        echo "PORT from ${PORTS[0]} to ${PORTS[1]}"
    fi

    aws_new_security_group_rule_create

    if $VERBOSE; then
        echo $ADD_SECURITY_GROUP_RULE_AWS_RESPONSE
    fi
    return 0
}

check_security_group_rules_availability(){
    if ! $FRESH_MODE; then
        aws_get_security_group_rule_id $SG_DESCRIPTION
    else
        aws_get_security_group_rule_id $AWS_USERNAME
    fi
    OLD_SECURITY_GROUP_RULE_IDS=($OLD_SECURITY_GROUP_RULE_IDS_LIST)

    # If there is no rule, exit function
    if [[ -z $OLD_SECURITY_GROUP_RULE_IDS ]]; then
        if $VERBOSE; then
            if ! $FRESH_MODE; then
                echo
                echo "There is no old security group rule for this computer $SG_DESCRIPTION"
                echo
            else
                echo
                echo "There is no old security group rule for aws user $AWS_USERNAME"
                echo
            fi
        fi
        return 1
    fi
    return 0
}

clear_old_security_group_rule(){
    if ! check_security_group_rules_availability; then
        return 1
    fi

    if $VERBOSE; then
        echo
        echo "-----Delete OLD INGRESS RULE(s) from security group $SECURITY_GROUP_IDS in region $REGION-----"
    fi

    if ! $YES_MODE; then
        echo
        list_security_group_rules
        echo "Delete all listed old rules?"
        yes_no_choice
    fi

    for ((oldRuleIndex = 0; oldRuleIndex < ${#OLD_SECURITY_GROUP_RULE_IDS[@]}; oldRuleIndex++)); do
        if $VERBOSE; then
            echo "+++Remove rule with id ${OLD_SECURITY_GROUP_RULE_IDS[oldRuleIndex]}+++"
        fi

        aws_clear_old_security_group_rule

        if $VERBOSE; then
            echo $CLEAR_SECURITY_GROUP_RULE_AWS_RESPONSE
        fi
    done

    if $CLEAR_MODE; then
        exit 1
    fi

    return 0
}

display(){
    if ! $VERBOSE; then
        return 1
    fi
    echo
    echo "Now the script $0 is invoked with description as \"$SG_DESCRIPTION\""
    echo "Regions: $REGION"
    echo "Security Group ID: ${SECURITY_GROUP_IDS[@]}"
    echo "Port range: ${PORTS[0]}-${PORTS[1]}"
    echo "Current IP address is \"$CURRENT_IP_ADDRESS\""
    return 0
}

# Initialize necessary variables which are used in the script
initialize(){
    echo
    # Check the availability of security group ID
    if [[ -z $SECURITY_GROUP_IDS ]]; then
        echo
        echo "Please input Security-Group-ID by following the syntax \"./`basename "$0"` -s security-group-id\""
        exit 1
    fi

    if [[ -z $CURRENT_IP_ADDRESS ]]; then
        CURRENT_IP_ADDRESS=$(curl -ssS https://checkip.amazonaws.com)                 # Check current address with AWS service
    fi

    if $VERBOSE; then
        echo "Current IP address to add to security group \"$CURRENT_IP_ADDRESS\""
    fi

    AWS_USERNAME=$(aws iam get-user --output text --query 'User.UserName')
    SG_DESCRIPTION="$AWS_USERNAME-$(hostname)-dev-machine"

    if [[ -z $PORTS ]]; then
        PORTS=(22 22)			                                                              # SSH port is 22 by default.
    fi

    aws_get_security_group_availability_zone
}

is_number(){
    re='^[0-9]+$'
    if ! [[ $1 =~ $re ]] ; then
        return 1    # Not number
    else
        return 0    # Number
    fi
}

list_security_group_rules(){
    if ! $FRESH_MODE; then
        echo "Available old security group rule id for current computer \"$SG_DESCRIPTION\" is:"
        echo "$OLD_SECURITY_GROUP_RULE_IDS"
    else
        echo "There is(are) ${#OLD_SECURITY_GROUP_RULE_IDS[@]} old security group rule id(s) for current AWS user \"$AWS_USERNAME\":"
        echo "${OLD_SECURITY_GROUP_RULE_IDS[@]}"
    fi

    if $LIST_MODE; then
        exit 1                    # turn off the script after listing the rules id in LIST mode
    fi

    return 0
}

yes_no_choice(){
  if ! $VERBOSE; then
      return 1
  fi
  if ! $YES_MODE; then
      echo -n "Press Y to continue, N to end the program (Y/N)? "
      while read -r -n 1 -s answer; do
          if [[ $answer = [YyNn] ]]; then
            [[ $answer = [Nn] ]] && echo && exit 1
            break
          fi
      done

      echo # Add an empty line for easier text reading
  fi
}

###################################################################################################################################################
### AWS FUNCTIONS ##################################################################################################################################
###################################################################################################################################################
aws_new_security_group_rule_create(){
  ADD_SECURITY_GROUP_RULE_AWS_RESPONSE=$(aws ec2 authorize-security-group-ingress \
                                        --group-id $SECURITY_GROUP_IDS \
                                        --ip-permissions IpProtocol=tcp,FromPort=${PORTS[0]},ToPort=${PORTS[1]},IpRanges="[{CidrIp=$CURRENT_IP_ADDRESS/32,Description=\"$SG_DESCRIPTION\"}]" \
                                        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key="Owner",Value="$SG_DESCRIPTION"}]")
}

aws_clear_old_security_group_rule(){
  CLEAR_SECURITY_GROUP_RULE_AWS_RESPONSE=$(aws ec2 revoke-security-group-ingress \
                                          --group-id $SECURITY_GROUP_IDS \
                                          --security-group-rule-ids ${OLD_SECURITY_GROUP_RULE_IDS[oldRuleIndex]})
}

aws_get_security_group_rule_id(){
  OLD_SECURITY_GROUP_RULE_IDS_LIST=$(aws ec2 describe-security-group-rules \
                                    --filter Name="group-id",Values="$SECURITY_GROUP_IDS" \
                                    --filter Name="tag:Owner",Values="$1*" \
                                    --output text --query 'SecurityGroupRules[*].SecurityGroupRuleId')
}

aws_get_security_group_availability_zone(){
  REGION="$(aws ec2 describe-network-interfaces \
           --filter Name="group-id",Values="$SECURITY_GROUP_IDS" \
           --output text --query 'NetworkInterfaces[*].AvailabilityZone')"    # Check security group's region
}
###################################################################################################################################################
### MAIN PROGRAM ##################################################################################################################################
###################################################################################################################################################
VERBOSE=false                     # Turn off verbose mode automatically
YES_MODE=false                    # Turn off yes mode automatically
FRESH_MODE=false                  # Turn off fresh mode automatically
LIST_MODE=false                   # Turn off list mode automatically
CLEAR_MODE=false                  # Turn off clear mode automatically

# Check argument parsing (can not be put in function)
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do          # loop through arguments with Positional Parameter $0
  case $1 in                      # Positional Parameter $1 comes to the argument
    -c|--clear-rules)
      CLEAR_MODE=true
      shift                       # Shift Positional Parameter $0 to the argument position (past argument)
      ;;
    -f|--fresh-mode)
      FRESH_MODE=true
      shift                       # Shift Positional Parameter $0 to the argument position (past argument)
      ;;
    -h|--help)
      help
      exit 1
      ;;
    -i|--ip)
      CURRENT_IP_ADDRESS=$2       # Positional Parameter $2 comes to the value
      shift                       # Shift Positional Parameter $0 to the argument position (past argument)
      shift                       # Shift Positional Parameter $0 to the value position (past value)
      ;;
    -l|--list-rules)
      LIST_MODE=true
      shift                       # Shift Positional Parameter $0 to the argument position (past argument)
      ;;
    -p|--port)
      PORTS=($2)                  # Set the starting port
      if is_number $3; then
          PORTS+=($3)             # Set the ending port
          shift                   # Shift Positional Parameter $0 to the second value position (past second value)
      else
          PORTS+=($2)             # Set the ending port the same as the starting port
      fi
      shift                       # Shift Positional Parameter $0 to the argument position (past argument)
      shift                       # Shift Positional Parameter $0 to the first value position (past first value)
      ;;
    -s|--security-group-id)
      SECURITY_GROUP_IDS=$2
      shift                       # Shift Positional Parameter $0 to the argument position (past argument)
      shift                       # Shift Positional Parameter $0 to the value position (past value)
      ;;
    -v|--verbose)
      VERBOSE=true
      shift                       # Shift Positional Parameter $0 to the argument position (past argument)
      ;;
    -y|--yes-mode)
      YES_MODE=true
      shift                       # Shift Positional Parameter $0 to the argument position (past argument)
      ;;
    -*|--*)                       # Wrong argument options input
      echo "Unknown option $1"
      help
      exit 1
      ;;
    *)                            # Ignore argument input if it does not begin with "-" or "--" sign
      POSITIONAL_ARGS+=("$1")     # save positional arg
      shift                       # Shift Positional Parameter $0 to the argument position (past argument)
      ;;
  esac
done
# set -- "${POSITIONAL_ARGS[@]}"    # restore positional parameters for further use of $1, $2, etc. in normal way if necessary.
# Finish checking argument parsing

initialize
display
clear_old_security_group_rule
add_new_security_group_rule

