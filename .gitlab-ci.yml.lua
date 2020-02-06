stages:
    - syntax

.centos7_luac:
    image: centos:7
    before_script:
        - yum install -q -y epel-release
        - yum install -q -y lua

.check-syntax:
    extends: centos7_luac
    stage: syntax
    
    script:
        - luac GroupCalendar_ImportData.lua GroupCalendar_ImportDataEnums.lua -o GroupCalendar.luac
        
        
check-syntax:
    extends: .check-syntax
