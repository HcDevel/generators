#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
Java Bindings Generator
Copyright (C) 2012-2013 Matthias Bolte <matthias@tinkerforge.com>
Copyright (C) 2011-2013 Olaf Lüke <olaf@tinkerforge.com>

generate_java_bindings.py: Generator for Java bindings

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

import datetime
import sys
import os

sys.path.append(os.path.split(os.getcwd())[0])
import common
import java_common

class JavaBindingsDevice(java_common.JavaDevice):
    def get_java_import(self):
        include = """{0}
package com.tinkerforge;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.Arrays;
import java.util.List;
"""
        date = datetime.datetime.now().strftime("%Y-%m-%d")
        version = common.get_changelog_version(self.get_generator().get_bindings_root_directory())

        return include.format(common.gen_text_star.format(date, *version))

    def get_java_class(self):
        class_str = """
/**
 * {1}
 */
public class {0} extends Device {{
\tpublic final static int DEVICE_IDENTIFIER = {2};

"""

        return class_str.format(self.get_java_class_name(),
                                self.get_description(),
                                self.get_device_identifier())

    def get_matlab_callback_data_objects(self):
        objs = ''
        obj = """
\tpublic class {0}CallbackData extends java.util.EventObject {{
\t\tprivate static final long serialVersionUID = 1L;

{1}

\t\tpublic {0}CallbackData(Object device{3}) {{
\t\t\tsuper(device);

{4}
\t\t}}

\t\tpublic String toString() {{
\t\t\treturn "[" + {2} "]";
\t\t}}
\t}}
"""
        param = '\t\tpublic {0}{1} {2}{3};'
        for packet in self.get_packets('callback'):
            if packet.has_prototype_in_device():
                continue

            name = packet.get_java_object_name()
            params = []
            tostr = []
            assignments = []
            for element in packet.get_elements():
                typ = element.get_java_type()
                ele_name = element.get_headless_camel_case_name()
                if element.get_cardinality() > 1 and element.get_type() != 'string':
                    arr = '[]'
                    new = ' = new {0}[{1}]'.format(typ, element.get_cardinality())
                    to = '"{0} = " + Arrays.toString({0}) +'.format(ele_name)
                else:
                    arr = ''
                    new = ''
                    to = '"{0} = " + {0} +'.format(ele_name)

                tostr.append(to)
                params.append(param.format(typ, arr, ele_name, new))

                assignments.append('\t\t\tthis.{0} = {0};'.format(ele_name));

            signature_params = packet.get_java_parameter_list()
            if len(signature_params) > 0:
                signature_params = ', ' + signature_params

            objs += obj.format(name,
                               '\n'.join(params),
                               ' ", " + '.join(tostr),
                               signature_params,
                               '\n'.join(assignments))

        return objs

    def get_java_return_objects(self):
        objs = ''
        obj = """
\tpublic class {0} {{
{1}

\t\tpublic String toString() {{
\t\t\treturn "[" + {2} "]";
\t\t}}
\t}}
"""
        param = '\t\tpublic {0}{1} {2}{3};'
        for packet in self.get_packets('function'):
            if packet.has_prototype_in_device():
                continue
            if len(packet.get_elements('out')) < 2:
                continue

            name = packet.get_java_object_name()

            params = []
            tostr = []
            for element in packet.get_elements():
                typ = element.get_java_type()
                ele_name = element.get_headless_camel_case_name()
                if element.get_cardinality() > 1 and element.get_type() != 'string':
                    arr = '[]'
                    new = ' = new {0}[{1}]'.format(typ, element.get_cardinality())
                    to = '"{0} = " + Arrays.toString({0}) +'.format(ele_name)
                else:
                    arr = ''
                    new = ''
                    to = '"{0} = " + {0} +'.format(ele_name)

                tostr.append(to)
                params.append(param.format(typ, arr, ele_name, new))

            objs += obj.format(name,
                               '\n'.join(params),
                               ' ", " + '.join(tostr))

        return objs

    def get_java_listener_definitions(self):
        cbs = ''
        cb = """
\t/**
\t * {3}
\t */
\tpublic interface {0}Listener extends DeviceListener {{
\t\tpublic void {1}({2});
\t}}
"""
        for packet in self.get_packets('callback'):
            name = packet.get_camel_case_name()
            name_lower = packet.get_headless_camel_case_name()

            if self.get_generator().is_matlab():
                parameter = name + 'CallbackData data'
            else:
                parameter = packet.get_java_parameter_list()

            doc = packet.get_java_formatted_doc()
            cbs += cb.format(name, name_lower, parameter, doc)
        return cbs

    def get_java_response_expected(self):
        res = ''
        re = "\t\tresponseExpected[IPConnection.unsignedByte({0})] = {1}\n"

        for packet in self.get_packets('function'):
            name_upper = 'FUNCTION_' + packet.get_upper_case_name()
            setto = 'RESPONSE_EXPECTED_FLAG_FALSE;'
            if len(packet.get_elements('out')) > 0:
                setto = 'RESPONSE_EXPECTED_FLAG_ALWAYS_TRUE;'
            elif packet.get_doc()[0] == 'ccf':
                setto = 'RESPONSE_EXPECTED_FLAG_TRUE;'

            res += re.format(name_upper, setto)

        for packet in self.get_packets('callback'):
            name_upper = 'CALLBACK_' + packet.get_upper_case_name()
            setto = 'RESPONSE_EXPECTED_FLAG_ALWAYS_FALSE;'
            res += re.format(name_upper, setto)

        return res

    def get_java_callback_listener_definitions(self):
        cbs = ''
        cb = """
\t\tcallbacks[CALLBACK_{0}] = new IPConnection.DeviceCallbackListener() {{
\t\t\tpublic void callback({5}byte[] data) {{{1}
\t\t\t\tfor({2}Listener listener: listener{2}) {{
\t\t\t\t\tlistener.{3}({4});
\t\t\t\t}}
\t\t\t}}
\t\t}};
"""

        data = """
\t\t\t\tByteBuffer bb = ByteBuffer.wrap(data, 8, data.length - 8);
\t\t\t\tbb.order(ByteOrder.LITTLE_ENDIAN);

{1}"""
        cbs_end = '\t}\n'
        for packet in self.get_packets('callback'):
            typ = packet.get_upper_case_name()
            name = packet.get_camel_case_name()
            name_lower = packet.get_headless_camel_case_name()
            parameter = ''
            parameter_list = []
            for element in packet.get_elements():
                parameter_list.append(element.get_headless_camel_case_name())
            parameter = ', '.join(parameter_list)
            cbdata = ''
            if len(packet.get_elements('out')) > 0:
                bbgets, bbret = packet.get_java_bbgets()
                bbgets = bbgets.replace('\t\t', '\t\t\t\t')
                cbdata = data.format(name_lower,
                                     bbgets,
                                     bbret)

            device_param = ''

            if self.get_generator().is_matlab():
                if len(parameter) > 0:
                    parameter = ', ' + parameter
                parameter = 'new {0}CallbackData(device{1})'.format(name, parameter)
                device_param = 'Device device, '

            cbs += cb.format(typ, cbdata, name, name_lower, parameter, device_param)
        return cbs + cbs_end

    def get_java_add_listener(self):
        if self.get_callback_count() == 0:
            return '}'

        listeners = ''
        listener = """
\t/**
\t * Adds a {0} listener.
\t */
\tpublic void add{0}Listener({0}Listener listener) {{
\t\tlistener{0}.add(listener);
\t}}

\t/**
\t * Removes a {0} listener.
\t */
\tpublic void remove{0}Listener({0}Listener listener) {{
\t\tlistener{0}.remove(listener);
\t}}
"""

        l = []
        for packet in self.get_packets('callback'):
            name = packet.get_camel_case_name()
            listeners += listener.format(name)
        return listeners + '}'

    def get_java_function_id_definitions(self):
        function_ids = ''
        function_id = '\tpublic final static byte {2}_{0} = (byte){1};\n'
        for packet in self.get_packets():
            function_ids += function_id.format(packet.get_upper_case_name(),
                                               packet.get_function_id(),
                                               packet.get_type().upper())
        return function_ids

    def get_java_constants(self):
        constant = '\tpublic final static {0} {1}_{2} = {3}{4};\n'
        constants = []
        for constant_group in self.get_constant_groups():
            type = java_common.get_java_type(constant_group.get_type())

            for constant_item in constant_group.get_items():
                if constant_group.get_type() == 'char':
                    cast = ''
                    value = "'{0}'".format(constant_item.get_value())
                else:
                    cast = '({0})'.format(type)
                    value = str(constant_item.get_value())

                constants.append(constant.format(type,
                                                 constant_group.get_upper_case_name(),
                                                 constant_item.get_upper_case_name(),
                                                 cast,
                                                 value))
        return '\n' + ''.join(constants)

    def get_java_listener_lists(self):
        llists = '\n'
        llist = '\tprivate List<{0}Listener> listener{0} = new CopyOnWriteArrayList<{0}Listener>();\n'
        for packet in self.get_packets('callback'):
            name = packet.get_camel_case_name()
            llists += llist.format(name)

        return llists

    def get_java_constructor(self):
        con = """
\t/**
\t * Creates an object with the unique device ID \c uid. and adds it to
\t * the IP Connection \c ipcon.
\t */
\tpublic {0}(String uid, IPConnection ipcon) {{
\t\tsuper(uid, ipcon);

\t\tapiVersion[0] = {1};
\t\tapiVersion[1] = {2};
\t\tapiVersion[2] = {3};
"""

        return con.format(self.get_java_class_name(), *self.get_api_version())

    def get_java_methods(self):
        methods = ''
        method = """
\t/**
\t * {8}
\t */
\tpublic {0} {1}({2}) {3} {{
\t\tByteBuffer bb = ipcon.createRequestPacket((byte){4}, FUNCTION_{5}, this);
{6}
{7}
\t}}
"""
        method_response = """\t\tbyte[] response = sendRequest(bb.array());

\t\tbb = ByteBuffer.wrap(response, 8, response.length - 8);
\t\tbb.order(ByteOrder.LITTLE_ENDIAN);

{1}
\t\treturn {2};"""

        method_noresponse = """\t\tsendRequest(bb.array());"""

        loop = """\t\tfor(int i = 0; i < {0}; i++) {{
{1}
\t\t}}
"""
        string_loop = """\t\ttry {{
\t\t{0}
\t\t\t}} catch(Exception e) {{
\t\t\t\tbb.put((byte)0);
\t\t\t}}"""

        cls = self.get_camel_case_name()
        for packet in self.get_packets('function'):
            options = 0
            ret = packet.get_java_return_type()
            name_lower = packet.get_headless_camel_case_name()
            parameter = packet.get_java_parameter_list()
            size = str(packet.get_request_size())
            name_upper = packet.get_upper_case_name()
            doc = packet.get_java_formatted_doc()
            bbputs = ''
            bbput = '\t\tbb.put{0}({1}{2});'
            for element in packet.get_elements('in'):
                name = element.get_headless_camel_case_name()
                if element.get_type() == 'bool':
                    name = '({0} ? 1 : 0)'.format(name)

                cast = ''
                storage_type = element.get_java_byte_buffer_storage_type()
                if storage_type != element.get_java_type():
                    cast = '({0})'.format(storage_type)

                bbput_format = bbput.format(element.get_java_byte_buffer_method_suffix(),
                                            cast,
                                            name)

                if element.get_cardinality() > 1:
                    if element.get_type() == 'string':
                        bbput_format = bbput_format.replace(');', '.charAt(i));')
                        bbput_format = string_loop.format(bbput_format)
                    else:
                        bbput_format = bbput_format.replace(');', '[i]);')
                    bbput_format = loop.format(element.get_cardinality(), '\t' + bbput_format)

                bbputs += bbput_format + '\n'

            throw = 'throws TimeoutException, NotConnectedException'
            if len(packet.get_elements('out')) == 0:
                bbgets = ''
                bbret = ''
            elif len(packet.get_elements('out')) > 1:
                bbgets, bbret = packet.get_java_bbgets(True)
                obj_name = packet.get_java_object_name()
                obj = '\t\t{0} obj = new {0}();\n'.format(obj_name)
                bbgets = obj + bbgets
                bbret = 'obj'
            else:
                bbgets, bbret = packet.get_java_bbgets(False)

            if len(packet.get_elements('out')) == 0:
                response = method_noresponse.format(name_upper)
            else:
                response = method_response.format(name_upper,
                                                  bbgets,
                                                  bbret)

            methods += method.format(ret,
                                     name_lower,
                                     parameter,
                                     throw,
                                     size,
                                     name_upper,
                                     bbputs,
                                     response,
                                     doc)

        return methods

    def get_java_source(self):
        source  = self.get_java_import()
        source += self.get_java_class()
        source += self.get_java_function_id_definitions()
        source += self.get_java_constants()
        source += self.get_java_listener_lists()

        if self.get_generator().is_matlab():
            source += self.get_matlab_callback_data_objects()

        source += self.get_java_return_objects()
        source += self.get_java_listener_definitions()
        source += self.get_java_constructor()
        source += self.get_java_response_expected()
        source += self.get_java_callback_listener_definitions()
        source += self.get_java_methods()
        source += self.get_java_add_listener()

        return source

class JavaBindingsPacket(java_common.JavaPacket):
    def get_java_formatted_doc(self):
        text = common.select_lang(self.get_doc()[1])
        link = '{{@link {0}#{1}({2})}}'
        link_c = '{{@link {0}.{1}Listener}}'

        # handle tables
        lines = text.split('\n')
        replaced_lines = []
        in_table_head = False
        in_table_body = False

        for line in lines:
            if line.strip() == '.. csv-table::':
                in_table_head = True
                replaced_lines.append('\\verbatim')
            elif line.strip().startswith(':header: ') and in_table_head:
                replaced_lines.append(line[len(':header: '):])
            elif line.strip().startswith(':widths:') and in_table_head:
                pass
            elif len(line.strip()) == 0 and in_table_head:
                in_table_head = False
                in_table_body = True

                replaced_lines.append('')
            elif len(line.strip()) == 0 and in_table_body:
                in_table_body = False

                replaced_lines.append('\\endverbatim')
                replaced_lines.append('')
            else:
                replaced_lines.append(line)

        text = '\n'.join(replaced_lines)

        cls = self.get_device().get_java_class_name()
        for other_packet in self.get_device().get_packets():
            name_false = ':func:`{0}`'.format(other_packet.get_camel_case_name())
            if other_packet.get_type() == 'callback':
                name = other_packet.get_camel_case_name()
                name_right = link_c.format(cls, name)
            else:
                name = other_packet.get_headless_camel_case_name()
                name_right = link.format(cls, name, other_packet.get_java_parameter_list(just_types=True))

            text = text.replace(name_false, name_right)

        text = text.replace('Callback ', 'Listener ')
        text = text.replace(' Callback', ' Listener')
        text = text.replace('callback ', 'listener ')
        text = text.replace(' callback', ' listener')
        text = text.replace('.. note::', '\\note')
        text = text.replace('.. warning::', '\\warning')

        def format_parameter(name):
            return '\c {0}'.format(name) # FIXME

        text = common.handle_rst_param(text, format_parameter)
        text = common.handle_rst_word(text)
        text = common.handle_rst_substitutions(text, self)
        text += common.format_since_firmware(self.get_device(), self)

        return '\n\t * '.join(text.strip().split('\n'))

    def get_java_bbgets(self, with_obj=False):
        bbgets = ''
        bbget_other = '\t\t{0}{1}{2} = {3}(bb.get{4}(){5}){6};'
        bbget_string = '\t\t{0}{1}{2} = {3}(bb{4}{5}){6};'
        new_arr ='{0}[] {1} = new {0}[{2}];'
        loop = """\t\t{2}for(int i = 0; i < {0}; i++) {{
{1}
\t\t}}
"""
        for element in self.get_elements('out'):
            typ = ''
            if not with_obj:
                typ = element.get_java_type() + ' '

            bbret = element.get_headless_camel_case_name()
            obj = ''
            if with_obj:
                obj = 'obj.'
            cast = ''
            cast_extra = ''
            boolean = ''
            if element.get_type() == 'uint8':
                cast = 'IPConnection.unsignedByte'
            elif element.get_type() == 'uint16':
                cast = 'IPConnection.unsignedShort'
            elif element.get_type() == 'uint32':
                cast = 'IPConnection.unsignedInt'
            elif element.get_type() == 'bool':
                boolean = ' != 0'
            elif element.get_type() == 'char':
                cast = '(char)'
            elif element.get_type() == 'string':
                cast = 'IPConnection.string'
                cast_extra = ', {0}'.format(element.get_cardinality())

            format_typ = ''
            if not element.get_cardinality() > 1 or (element.get_type() == 'string' and not with_obj):
                format_typ = typ

            if element.get_type() == 'string':
                bbget = bbget_string
            else:
                bbget = bbget_other

            bbget_format = bbget.format(format_typ,
                                        obj,
                                        bbret,
                                        cast,
                                        element.get_java_byte_buffer_method_suffix(),
                                        cast_extra,
                                        boolean)

            if element.get_cardinality() > 1 and element.get_type() != 'string':
                if with_obj:
                    bbget_format = bbget_format.replace(' =', '[i] =')
                    bbget_format = loop.format(element.get_cardinality(), '\t' + bbget_format, '')
                else:
                    arr = new_arr.format(typ.replace(' ', ''), bbret, element.get_cardinality())
                    bbget_format = bbget_format.replace(' =', '[i] =')
                    bbget_format = loop.format(element.get_cardinality(), '\t' + bbget_format, arr + '\n\t\t')

            bbgets += bbget_format + '\n'

        return bbgets, bbret

class JavaBindingsGenerator(common.BindingsGenerator):
    released_files_name_prefix = 'java'

    def get_bindings_name(self):
        return 'java'

    def get_device_class(self):
        return JavaBindingsDevice

    def get_packet_class(self):
        return JavaBindingsPacket

    def get_element_class(self):
        return java_common.JavaElement

    def generate(self, device):
        filename = '{0}.java'.format(device.get_java_class_name())

        java = open(os.path.join(self.get_bindings_root_directory(), 'bindings', filename), 'wb')
        java.write(device.get_java_source())
        java.close()

        if device.is_released():
            self.released_files.append(filename)

    def is_matlab(self):
        return False

def generate(bindings_root_directory):
    common.generate(bindings_root_directory, 'en', JavaBindingsGenerator)

if __name__ == "__main__":
    generate(os.getcwd())
