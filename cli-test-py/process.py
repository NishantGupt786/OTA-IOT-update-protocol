def read_cpu_temp():
    with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
        temp = int(f.read())
    print(f" Current CPU Temperature: {temp / 1000:.2f}°C")

read_cpu_temp()
