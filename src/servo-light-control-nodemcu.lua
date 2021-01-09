--wifi
staCfg = {}
staCfg.ssid = "MY_SSID"
staCfg.pwd = "MY_PWD"
wifi.setmode(wifi.STATION)
wifi.sta.config(staCfg)

--pwm
servoFrq = 50
servoPin = 1
servoOn = 27
servoOff = 100
servoMid = 63
pwmDelay = 25000
pwm.setup(servoPin, servoFrq, servoMid)
pwm.start(servoPin)
lightStatus = true

--mqtt
mMqtt = mqtt.Client("nodeMcu", 120)
tpRoot = "node"..tostring(node.chipid())
tpOnoff = tpRoot.."/onoff"
tpStatus = tpRoot.."/status"
tpSchedule = tpRoot.."/schedule"
gpio.mode(0,gpio.OUTPUT)
schedJSONObj = {}
schedArray = {}
index = 0

tmrWifi = tmr.create()
tmrWifi:alarm(2000, tmr.ALARM_AUTO, function()
    ip, netmask, gateway = wifi.sta.getip()
    print("ip=", ip)
    if ip ~= nil then
        tmrWifi:stop()
        sntp.sync("tock.stdtime.gov.tw",
                function(sec, usec, server, info)
                    rtctime.set(sec + 28800)
                    print('sync', sec, usec, server, info)
                end,
                function()
                    print('failed!')
                end)
        mMqtt:connect("192.168.0.103", 1883, false, function(m)
            print("connect to mqtt, root topic:", tpRoot)
            timer0=tmr.create()
            timer0:alarm(5000,tmr.ALARM_AUTO,function()
                printRTC()
            end)
            m:subscribe({ [tpOnoff] = 0, [tpSchedule] = 0}, 0, function(m)
                print("subscribe to ", tpOnoff)
                print("subscribe to ", tpSchedule)
            end)
            m:on("message", function(m, topic, data)
                print(topic, ":", data)
                if topic == tpOnoff then
                    if data == "true" then
                        setServo(true)
                    elseif data == "false" then
                        setServo(false)
                    end
                elseif topic == tpSchedule then
                    schedJSONObj = sjson.decode(data)
                    updateSchedule()
                end
            end)
        end,
        function(client, reason)
            print("failed reason: " .. reason)
            node.restart()
        end)
    end
end)

function printRTC()
    local tm = rtctime.epoch2cal(rtctime.get())
    print(string.format("%04d/%02d/%02d %02d:%02d:%02d", tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"]))
end

function setServo(onoff)
    if onoff then
        print("turn on")
        for i = servoMid, servoOn, -2 do
            pwm.start(servoPin)
            pwm.setduty(servoPin, i)
            tmr.delay(pwmDelay)
            pwm.stop(servoPin)
        end
        tmr.delay(pwmDelay*5)
        gpio.write(0,gpio.LOW)
        for i = servoOn, servoMid, 2 do
            pwm.start(servoPin)
            pwm.setduty(servoPin, i)
            tmr.delay(pwmDelay)
            pwm.stop(servoPin)
        end
    else
        print("turn off")
        for i = servoMid, servoOff, 2 do
            pwm.start(servoPin)
            pwm.setduty(servoPin, i)
            tmr.delay(pwmDelay)
            pwm.stop(servoPin)
        end
        tmr.delay(pwmDelay*5)
        gpio.write(0,gpio.HIGH)
        for i = servoOff, servoMid, -2 do
            pwm.start(servoPin)
            pwm.setduty(servoPin, i)
            tmr.delay(pwmDelay)
            pwm.stop(servoPin)
        end
    end
    lightStatus = onoff
    mMqtt:publish(tpStatus, tostring(lightStatus), 0, 1, function(client)
        print("update onoff status: ", lightStatus)
    end)
end

function updateSchedule()
    i = 1
    cron.reset()
    schedArray = {}
    while schedJSONObj[i] ~= nil do
        ent = cron.schedule(schedJSONObj[i]["cron"], function(e)
            local index = getIndexOf(e)
            print("Schedule", index, schedJSONObj[index]["onoff"])
            if schedJSONObj[index]["onoff"] == true then
                setServo(true)
            elseif schedJSONObj[index]["onoff"] == false then
                setServo(false)
            end
            printRTC()
        end)
        schedArray[i] = ent
        index = getIndexOf(ent)
        print("arr size:", #schedArray, "index:", index)
        print(index, schedJSONObj[index]["onoff"], schedJSONObj[index]["cron"])
        i = i + 1
    end
end

function getIndexOf(ent)
    print("ent", ent)
    for i = 1,#schedArray do
        print("k:", i, "v:", schedArray[i])
        if schedArray[i] == ent then
            return i
        end
    end
    return 0
end
