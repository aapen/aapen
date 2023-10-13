# Soft reset for Raspberry Pi when connected via OpenOCD
#
# From gdb, run "source tools/soft_reset.py"
#
# Usage:
#   soft_reset
#
# Settings:
#   none

import gdb

class SoftReset(gdb.Command):
    def __init__(self):
        super (SoftReset, self).__init__ ('soft_reset', gdb.COMMAND_DATA)

    def load_devicetree(self, inferior):
        devicetree_bin_path = gdb.parameter('devicetree-bin-file')
        if devicetree_bin_path == '':
            devicetree_bin_path = 'test/resources/fdt_model_3b_as_loaded.bin'

        with open(devicetree_bin_path, 'rb') as f:
            content = f.read()

        target_address = gdb.parameter('devicetree-memory-location')

        # Inferior's memory write
        inferior.write_memory(target_address, content)
        return target_address

    def reset_cpu_state(self, inferior, dt_ptr):
        gdb.execute(f"interrupt")
        gdb.execute(f"set $x0 = {hex(dt_ptr)}")
        gdb.execute(f"set $x1 = 'main.kernelInit'")
        gdb.execute(f"set $pc = soft_reset")
        print("Run 'continue' at the gdb prompt to reset")

    def invoke(self, arg, from_tty):
        inferior = gdb.selected_inferior()

        # Reload the devicetree file
        dt_ptr = self.load_devicetree(inferior)
        self.reset_cpu_state(inferior, dt_ptr)

class DevicetreeBinFile(gdb.Parameter):
    def __init__(self):
        super(DevicetreeBinFile, self).__init__('devicetree-bin-file', gdb.COMMAND_DATA, gdb.PARAM_STRING)

    set_doc = 'Path to a .bin file that will be reloaded as the device tree'
    show_doc = 'Device tree binary file path is currently'

class DevicetreeLocation(gdb.Parameter):
    def __init__(self):
        super(DevicetreeLocation, self).__init__('devicetree-memory-location', gdb.COMMAND_DATA, gdb.PARAM_UINTEGER)
        self.value = 0x2eff7a00

    def get_set_string(self):
        return f"Devicetree location is set to {hex(self.value)}."

    def get_show_string(self, svalue):
        return self.get_set_string()

    # Called when 'set devicetree-location <value>' is used
    def set(self, svalue):
        try:
            # Convert the string value to an integer (base auto-detection)
            self.value = int(svalue, 0)
        except ValueError:
            raise gdb.GdbError("Invalid memory address.")

    # Called when 'show devicetree-location' is used
    def get(self):
        return self.get_set_string()

    set_doc = 'Location in memory where the device tree file will be loaded'
    show_doc = 'Device tree binary memory location is currently'

SoftReset()
DevicetreeBinFile()
DevicetreeLocation()
