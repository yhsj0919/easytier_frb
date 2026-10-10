-- Demo 启动器：由系统授权框获取权限，不接触或保存管理员密码。
on run
    try
        set launcherPath to POSIX path of (path to me)
        set appDirectory to do shell script "/usr/bin/dirname " & quoted form of launcherPath
        set executablePath to appDirectory & "/easytier_frb_example.app/Contents/MacOS/easytier_frb_example"
        do shell script "/bin/test -x " & quoted form of executablePath

        -- 重定向标准流，让授权调用返回后应用仍可独立运行。
        set launchCommand to "/usr/bin/nohup " & quoted form of executablePath & " </dev/null >/dev/null 2>&1 & app_pid=$!; /bin/sleep 1; /bin/kill -0 \"$app_pid\""
        do shell script launchCommand with administrator privileges
    on error errorMessage number errorNumber
        if errorNumber is -128 then return -- 用户取消授权，不启动应用。
        display dialog "无法启动 EasyTier Demo。请确认两个应用在同一目录，并已允许打开下载的测试包。\n\n" & errorMessage buttons {"确定"} default button "确定" with icon stop
    end try
end run
