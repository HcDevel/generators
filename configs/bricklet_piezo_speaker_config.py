# -*- coding: utf-8 -*-

# Piezo Buzzer Bricklet communication config

com = {
    'author': 'Olaf Lüke <olaf@tinkerforge.com>',
    'api_version': [2, 0, 0],
    'category': 'Bricklet',
    'device_identifier': 242,
    'name': ('PiezoSpeaker', 'piezo_speaker', 'Piezo Speaker'),
    'manufacturer': 'Tinkerforge',
    'description': 'Device for controlling a piezo buzzer with configurable frequencies',
    'released': False,
    'packets': []
}

com['packets'].append({
'type': 'function',
'name': ('Beep', 'beep'), 
'elements': [('duration', 'uint32', 1, 'in'),
             ('frequency', 'uint16', 1, 'in')],
'since_firmware': [1, 0, 0],
'doc': ['bf', {
'en':
"""
Beeps with the given frequency value for the duration in ms. For example: 
If you set a duration of 1000, with a frequency value of 100
the piezo buzzer will beep for one second with a frequency of
approximately 2 kHz.

*frequency* can be set between 0 and 512.

Below you can find a graph that shows the relation between the frequency
value parameter and a frequency in Hz of the played tone:

.. image:: /Images/Bricklets/bricklet_piezo_speaker_value_to_frequency_graph.png
   :scale: 100 %
   :alt: Relation between value and frequency 
   :align: center

""",
'de':
"""
Erzeugt einen Piepton mit dem gegebenen Frequenzwert für eine Dauer in ms. 
Beispiel: Wenn *duration* auf 1000 und *frequency* auf 100 gesetzt wird, 
erzeugt der Piezosummer einen Piepton für eine Sekunde mit einer Frequenz 
von ca. 2 kHz.

*frequency* kann die Werte 0 bis 512 annehmen.

Im folgenden befindet sich ein Graph der die Relation zwischen dem
angegeben Frequenzwert und der Frequenz in Hz des gespieltens Tons
darstellt:

.. image:: /Images/Bricklets/bricklet_piezo_speaker_value_to_frequency_graph.png
   :scale: 100 %
   :alt: Relation zwischen Wert und Frequenz
   :align: center

"""
}]
})

com['packets'].append({
'type': 'function',
'name': ('MorseCode', 'morse_code'), 
'elements': [('morse', 'string', 60, 'in'),
             ('frequency', 'uint16', 1, 'in')],
'since_firmware': [1, 0, 0],
'doc': ['bf', {
'en':
"""
Sets morse code that will be played by the piezo buzzer. The morse code
is given as a string consisting of "." (dot), "-" (minus) and " " (space)
for *dits*, *dahs* and *pauses*. Every other character is ignored.
The second parameter is the frequency value (see :func:`Beep`).

For example: If you set the string "...---...", the piezo buzzer will beep
nine times with the durations "short short short long long long short 
short short".

The maximum string size is 60.
""",
'de':
"""
Setzt Morsecode welcher vom Piezosummer abgespielt wird. Der Morsecode wird
als Zeichenkette, mit den Zeichen "." (Punkt), "-" (Minus) und " " (Leerzeichen)
für *kurzes Signale*, *langes Signale* und *Pausen*. Alle anderen Zeichen
werden ignoriert.
Der zweite Parameter ist die Frequenzwert (see :func:`Beep`).

Beispiel: Wenn die Zeichenkette "...---..." gesetzt wird, gibt der Piezosummer neun
Pieptöne aus mit den Dauern "kurz kurz kurz lang lang lang kurz kurz kurz".

Die maximale Zeichenkettenlänge ist 60.
"""
}]
})

com['packets'].append({
'type': 'callback',
'name': ('BeepFinished', 'beep_finished'), 
'elements': [],
'since_firmware': [1, 0, 0],
'doc': ['c', {
'en':
"""
This callback is triggered if a beep set by :func:`Beep` is finished
""",
'de':
"""
Dieser Callback wird ausgelöst wenn ein Piepton, wie von :func:`Beep` gesetzt,
beendet wurde.
"""
}]
})

com['packets'].append({
'type': 'callback',
'name': ('MorseCodeFinished', 'morse_code_finished'), 
'elements': [],
'since_firmware': [1, 0, 0],
'doc': ['c', {
'en':
"""
This callback is triggered if the playback of the morse code set by
:func:`MorseCode` is finished.
""",
'de':
"""
Dieser Callback wird ausgelöst wenn die Wiedergabe des Morsecodes, wie von
:func:`MorseCode` gesetzt, beendet wurde.
"""
}]
})