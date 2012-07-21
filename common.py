# -*- coding: utf-8 -*-

"""
Common Generator Library
Copyright (C) 2012 Matthias Bolte <matthias@tinkerforge.com>
Copyright (C) 2011 Olaf Lüke <olaf@tinkerforge.com>

common.py: Common Library for generation of bindings and documentation

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public
License along with this program; if not, write to the
Free Software Foundation, Inc., 59 Temple Place - Suite 330,
Boston, MA 02111-1307, USA.
"""

import os
import shutil
import re
import datetime
import subprocess
import sys

gen_text_star = """/* ***********************************************************
 * This file was automatically generated on {0}.      *
 *                                                           *
 * If you have a bugfix for this file and want to commit it, *
 * please fix the bug in the generator. You can find a link  *
 * to the generator git on tinkerforge.com                   *
 *************************************************************/
"""

gen_text_hash = """#############################################################
# This file was automatically generated on {0}.      #
#                                                           #
# If you have a bugfix for this file and want to commit it, #
# please fix the bug in the generator. You can find a link  #
# to the generator git on tinkerforge.com                   #
#############################################################
"""

gen_text_rst = """..
 #############################################################
 # This file was automatically generated on {0}.      #
 #                                                           #
 # If you have a bugfix for this file and want to commit it, #
 # please fix the bug in the generator. You can find a link  #
 # to the generator git on tinkerforge.com                   #
 #############################################################
"""

def shift_right(text, n):
    return text.replace('\n', '\n' + ' '*n)

def get_changelog_version(path):
    r = re.compile('^(\d+)\.(\d+)\.(\d+):')
    last = None
    for line in file(path + '/changelog.txt').readlines():
        m = r.match(line)

        if m is not None:
            last = (m.group(1), m.group(2), m.group(3))

    return last

def get_type_size(typ):
    types = {
        'int8'   : 1,
        'uint8'  : 1,
        'int16'  : 2,
        'uint16' : 2,
        'int32'  : 4,
        'uint32' : 4,
        'int64'  : 8,
        'uint64' : 8,
        'float'  : 4,
        'bool'   : 1,
        'string' : 1,
        'char'   : 1
    }

    return types[typ]

def get_element_size(element):
    return get_type_size(element[1]) * element[2]

def make_rst_header(device, ref_name, title):
    date = datetime.datetime.now().strftime("%Y-%m-%d")
    ref = '.. _{0}_{1}_{2}:\n'.format(device.get_underscore_name(), device.get_category().lower(), ref_name)
    title = '{0} - {1} {2}'.format(title, device.get_display_name(), device.get_category())
    title_under = '='*len(title)
    return '{0}\n{1}\n{2}\n{3}\n'.format(gen_text_rst.format(date),
                                         ref,
                                         title,
                                         title_under)

def make_rst_summary(device, title):
    su = """
This is the API site for the {4} of the {0} {1}. General information
on what this device does and the technical specifications can be found
:ref:`here <{2}>`.

A tutorial on how to test the {0} {1} and get the first examples running
can be found :ref:`here <{3}>`.
"""

    hw_link = device.get_underscore_name() + '_' + device.get_category().lower()
    hw_test = hw_link + '_test'
    su = su.format(device.get_display_name(), device.get_category(), hw_link, hw_test, title)
    return su

def make_rst_examples(title_from_file, device, base_path, dirname, filename_prefix, filename_suffix, include_name):
    ex = """
{0}

Examples
--------

The example code below is public domain.
"""

    imp = """
{0}
{1}

`Download <https://github.com/Tinkerforge/{3}/raw/master/software/examples/{4}/{5}>`__

.. literalinclude:: {2}
 :language: {4}
 :linenos:
 :tab-width: 4
"""

    ref = '.. _{0}_{1}_{2}_examples:\n'.format(device.get_underscore_name(),
                                               device.get_category().lower(),
                                               dirname)
    ex = ex.format(ref)
    files = find_examples(device, base_path, dirname, filename_prefix, filename_suffix)
    copy_files = []
    for f in files:
        include = '{0}_{1}_{2}_{3}'.format(device.get_camel_case_name(), device.get_category(), include_name, f[0])
        copy_files.append((f[1], include))
        title = title_from_file(f[0])
        git_name = device.get_underscore_name().replace('_', '-') + '-' + device.get_category().lower()
        ex += imp.format(title, '^'*len(title), include, git_name, dirname, f[0])

    copy_examples(copy_files, base_path)
    return ex

def find_examples(device, base_path, dirname, filename_prefix, filename_suffix):
    start_path = base_path.replace('/generators/' + dirname, '')
    board = '{0}-{1}'.format(device.get_underscore_name(), device.get_category().lower())
    board = board.replace('_', '-')
    board_path = os.path.join(start_path, board, 'software/examples/' + dirname)
    files = []
    for f in os.listdir(board_path):
        if f.startswith(filename_prefix) and f.endswith(filename_suffix):
            f_dir = '{0}/{1}'.format(board_path, f)
            lines = 0
            for line in open(os.path.join(f, f_dir)):
                lines += 1
            files.append((f, f_dir, lines))

    files.sort(lambda i, j: cmp(i[2], j[2]))

    return files

def copy_examples(copy_files, path):
    doc_path = '{0}/doc'.format(path)
    print('  * Copying examples:')
    for copy_file in copy_files:
        doc_dest = '{0}/{1}'.format(doc_path, copy_file[1])
        doc_src = copy_file[0]
        shutil.copy(doc_src, doc_dest)
        print('   - {0}'.format(copy_file[1]))

def make_zip(dirname, source_path, dest_path, version):
    zipname = 'tinkerforge_{0}_bindings_{1}_{2}_{3}.zip'.format(dirname, *version)
    os.chdir(source_path)
    args = ['/usr/bin/zip',
            '-r',
            zipname,
            '.']
    subprocess.call(args)
    shutil.copy(zipname, dest_path)

re_camel_case_to_space = re.compile('([A-Z][A-Z][a-z])|([a-z][A-Z])')

def camel_case_to_space(name):
    return re_camel_case_to_space.sub(lambda m: m.group()[:1] + " " + m.group()[1:], name)

def underscore_to_headless_camel_case(name):
    parts = name.split('_')
    ret = parts[0]
    for part in parts[1:]:
        ret += part[0].upper() + part[1:]
    return ret

def generate(path, make_files):
    path_list = path.split('/')
    path_list[-1] = 'configs'
    path_config = '/'.join(path_list)
    sys.path.append(path_config)
    configs = os.listdir(path_config)

    common_packets = []
    try:
        configs.remove('brick_commonconfig.py')
        common_packets = __import__('brick_commonconfig').common_packets
    except:
        pass
    
    for config in configs:
        if config.endswith('_config.py'):
            module = __import__(config[:-3])
            print(" * {0}".format(config[:-10]))            
            if 'brick_' in config and not module.com.has_key('common_included'):
                module.com['packets'].extend(common_packets)
                module.com['common_included'] = True
            make_files(module.com, path)

class Packet:
    def __init__(self, packet):
        self.packet = packet
        self.all_elements = packet['elements']
        self.in_elements = []
        self.out_elements = []

        if packet['name'][0].lower() != packet['name'][1].replace('_', ''):
            raise ValueError('Name mismatch: ' + packet['name'][0] + ' != ' + packet['name'][1])

        for element in self.all_elements:
            if element[3] == 'in':
                self.in_elements.append(element)
            elif element[3] == 'out':
                self.out_elements.append(element)
            else:
                raise ValueError('Invalid element direction ' + element[3])

    def get_type(self):
        return self.packet['type']

    def get_camel_case_name(self):
        return self.packet['name'][0]

    def get_headless_camel_case_name(self):
        m = re.match('([A-Z]+)(.*)', self.packet['name'][0])
        return m.group(1).lower() + m.group(2)

    def get_underscore_name(self):
        return self.packet['name'][1]

    def get_upper_case_name(self):
        return self.packet['name'][1].upper()

    def get_elements(self, direction=None):
        if direction is None:
            return self.all_elements
        elif direction == 'in':
            return self.in_elements
        elif direction == 'out':
            return self.out_elements
        else:
            raise ValueError('Invalid element direction ' + str(direction))

    def get_doc(self):
        return self.packet['doc']

    def get_function_id(self):
        return self.packet['function_id']

    def get_request_length(self):
        length = 4
        for element in self.in_elements:
            length += get_element_size(element)
        return length

    def get_response_length(self):
        length = 4
        for element in self.out_elements:
            length += get_element_size(element)
        return length

class Device:
    def __init__(self, com):
        self.com = com
        self.all_packets = []
        self.function_packets = []
        self.callback_packets = []

        for i, packet in zip(range(len(com['packets'])), com['packets']):
            if not 'function_id' in packet:
                packet['function_id'] = i + 1
            self.all_packets.append(Packet(packet))

        for packet in self.all_packets:
            if packet.get_type() == 'function':
                self.function_packets.append(packet)
            elif packet.get_type() == 'callback':
                self.callback_packets.append(packet)
            else:
                raise ValueError('Invalid packet type ' + packet.get_type())

    def get_version(self):
        return self.com['version']

    def get_category(self):
        return self.com['category']

    def get_camel_case_name(self):
        return self.com['name'][0]

    def get_headless_camel_case_name(self):
        m = re.match('([A-Z]+)(.*)', self.com['name'][0])
        return m.group(1).lower() + m.group(2)

    def get_underscore_name(self):
        return self.com['name'][1]

    def get_upper_case_name(self):
        return self.com['name'][1].upper()

    # this is also the name stored in the firmware
    def get_display_name(self):
        return self.com['name'][2]

    def get_description(self):
        return self.com['description']

    def get_packets(self, typ=None):
        if typ is None:
            return self.all_packets
        elif typ == 'function':
            return self.function_packets
        elif typ == 'callback':
            return self.callback_packets
        else:
            raise ValueError('Invalid packet type ' + str(typ))

    def get_callback_count(self):
        return len(self.callback_packets)
