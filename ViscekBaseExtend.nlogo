globals [
  psi
  c
  hawk-roam-angle
  max-children
]

breed [doves dove]
breed [hawks hawk]

patches-own [
  my-turtle
]

doves-own [
  my-area
  n-children
  flock-assigned	
]

hawks-own[
  current-target

  carries-prey
  eating
  eating-spot
]

to setup
  clear-all

  ask patches [set pcolor white]

  create-doves n-doves [
    setxy random-pxcor random-pycor
    set color one-of [blue green yellow pink]
    set heading random 360
    set flock-assigned false
    set n-children 0
    set shape "bird"
  ]

  create-hawks n-hawks[
    set color red
    set shape "hawk"
    set size 2.5
    set current-target nobody
    set carries-prey false
    set eating -1
    set eating-spot one-of patches
    setxy random-pxcor random-pycor
  ]

  set psi 0
  set hawk-roam-angle 25
  set max-children 3
  reset-ticks
end


to go
  tick

  update-doves

  seek-and-destroy

  if count doves > 0 [
    set psi ((sum [dx] of doves) ^ 2 + (sum [cos heading] of doves)^ 2) ^ 0.5 / (count doves)
  ]

  if show-voronoi? [
    partition-world
  ]

  ifelse birth-on = "breeding-period" [
    if ticks mod breeding-period = 0 [
      breed-doves
    ]
  ] [
    if birth-on = "less-than-initial" [
      if count doves < n-doves [
        breed-doves
      ]
    ]
  ]

end

to give-birth [spouse]

  let nx (xcor + [xcor] of spouse) / 2
  let ny (ycor + [ycor] of spouse) / 2

  let self-color color
  let other-color [color] of spouse

  hatch 1 [
    setxy nx ny
    set color one-of (list self-color other-color)
    set heading random 360
    set flock-assigned false
    set n-children 0
    set shape "bird"
  ]

end

to breed-doves
  ask doves [
    if n-children < max-children[
      let spouse min-one-of other doves in-radius friendly-radius with [n-children < max-children] [distance myself]
      if spouse != nobody [
        give-birth spouse

        set n-children n-children + 1
        ask spouse [
          set n-children n-children + 1
        ]
      ]
   ]
  ]
end

to update-doves

  ask doves [
    ;compute the direction of flock
    let theta heading
    let a doves in-radius friendly-radius
    if a != nobody [
      set theta average-flockmate-heading a
    ]
    let in-flock-heading add-noise-to-heading heading-noise-range theta

    if-else any? hawks in-radius dove-enemy-vision[
      ;take into accoutn the presence of hawks and adjust the direction
      let threats hawks in-radius dove-enemy-vision
      let avg-hawk-direction optimal-hawk-avoiding-heading threats
      let fear-heading add-noise-to-heading dove-fear-dir-noise avg-hawk-direction

      let optimal-heading (((in-flock-heading - 180) * threat-ignorance + (fear-heading - 180) * (1 - threat-ignorance)) + 180)
      set heading optimal-heading

      fd dove-boost-speed + dove-standard-speed
    ][
      ;stay with the flock
      set heading in-flock-heading

      fd dove-standard-speed
    ]
 ]

end

to-report add-noise-to-heading [noise some-heading]
  let noisy-heading (some-heading + (random-float 2 * noise) - noise)
  if noisy-heading > 360 [
    report noisy-heading mod 360
  ]

  if noisy-heading < 0 [
    report 360 - ((abs noisy-heading) mod 360)
  ]

  report noisy-heading

end

to seek-and-destroy

  ask hawks [
    if-else current-target = nobody and carries-prey = false and eating = -1 [
      ;find a new prey
      if any? doves in-radius hawk-vision[
        set current-target one-of other doves in-radius hawk-vision
      ]
    ][
      ;the prey ma have dropped out of sight. Unlock it.
      if current-target != nobody and distance current-target > hawk-vision[
        set current-target nobody
      ]
    ]
  ]

  ask hawks[
    if-else current-target = nobody[
      if-else carries-prey = false [
        if-else eating = -1[

          ;wander around the world in search of prey
          set heading heading + (random (2 * hawk-roam-angle)) - hawk-roam-angle
          fd hawk-search-speed

        ][

          ;spend some time eating without any motion
          set eating eating + 1
          if eating >= time-to-eat [
            set eating -1
            set carries-prey false
            set current-target nobody

          ]
        ]
      ][

        ;fly to the eating spot
        set heading towardsxy [pxcor] of eating-spot [pycor] of eating-spot
        fd hawk-search-speed
        if distance eating-spot < 3 [
          set carries-prey false
          set eating 0
        ]

      ]
    ][
      ;follow prey
      set heading towardsxy [xcor] of current-target [ycor] of current-target
      fd hawk-hunt-speed

      ;catch a dove
      let closest-dove min-one-of doves in-radius 2 [distance myself]
      if closest-dove != nobody [
        ask closest-dove [die]
        set eating-spot []
        set eating-spot one-of patches in-radius 30
        set carries-prey true
        set current-target nobody
      ]
    ]
  ]


end

to partition-world
  ask patches [
    set my-turtle [who] of min-one-of doves [distance myself]
  ]

  define-clusters

  ask patches [
      set pcolor  my-turtle mod 255
  ]
end

to define-clusters
  ask doves [
    set my-area count patches with [my-turtle = [who] of myself]
  ]

  set c (count doves with [my-area < friendly-radius * friendly-radius * pi]) / (count doves)
end

to-report average-flockmate-heading [flockmates]  ;; turtle procedure
    ;; We can't just average the heading variables here.
    ;; For example, the average of 1 and 359 should be 0,
    ;; not 180. So we have to use trigonometry.
    let x-component mean [dx] of flockmates
    let y-component mean [dy] of flockmates
    ifelse x-component = 0 and y-component = 0
       [ report heading ]
       [ report atan x-component y-component ]
end

to-report optimal-hawk-avoiding-heading [hawks-threats]

  let dovex xcor
  let dovey ycor
  let x-comp mean [dovex - xcor] of hawks-threats
  let y-comp mean [dovey - ycor] of hawks-threats

  ifelse x-comp = 0 and y-comp = 0
       [ report heading ]
       [ report atan x-comp y-comp ]
end

to-report heading-variance
  let x-var variance [dx] of doves
  let y-var variance [dy] of doves

  report x-var + y-var
end

to grow-flock
  set flock-assigned true
  let neighbours other doves in-radius flock-size-threshold with [flock-assigned = false]

  ask neighbours
  [
    if flock-assigned = false ;;some may already be assigned as a result of previous iterations
    [
    	grow-flock
    ]
  ]
end

to-report count-groups
  ask doves
  [
    set flock-assigned false
  ]

	let n-groups 0

  ask doves
  [
    if flock-assigned = false
    [
      grow-flock
    	set n-groups n-groups + 1
    ]
  ]

  report n-groups
end
@#$#@#$#@
GRAPHICS-WINDOW
244
10
1169
936
-1
-1
9.08
1
10
1
1
1
0
1
1
1
-50
50
-50
50
0
0
1
ticks
30.0

BUTTON
23
16
89
49
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
23
50
89
83
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
19
127
191
160
n-doves
n-doves
10
1000
100.0
1
1
NIL
HORIZONTAL

SLIDER
19
160
191
193
friendly-radius
friendly-radius
0
20
20.0
0.01
1
NIL
HORIZONTAL

PLOT
1180
16
1653
266
global alignment coefficient
NIL
NIL
0.0
1.0
0.0
1.0
true
true
"" ""
PENS
"psi" 1.0 0 -16777216 true "" "plot psi"
"c" 1.0 0 -13345367 true "" "plot c"

BUTTON
90
50
157
83
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
1184
695
1318
729
show-voronoi?
show-voronoi?
1
1
-1000

PLOT
1182
284
1657
508
Alignment metric
NIL
NIL
0.0
10.0
0.0
2.0
true
false
"" ""
PENS
"Pen 1" 1.0 0 -5509967 true "" "plotxy ticks heading-variance"

SLIDER
1185
732
1315
766
flock-size-threshold
flock-size-threshold
1
100
16.0
1
1
NIL
HORIZONTAL

PLOT
1184
524
1694
684
N-flocks
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"Pen 1" 1.0 0 -9970062 true "" "plotxy ticks count-groups"

SLIDER
18
201
238
234
heading-noise-range
heading-noise-range
0.25
10
10.0
0.01
1
NIL
HORIZONTAL

SLIDER
20
649
192
682
n-hawks
n-hawks
0
10
0.0
1
1
NIL
HORIZONTAL

SLIDER
20
609
192
642
hawk-vision
hawk-vision
1
100
15.0
1
1
NIL
HORIZONTAL

SLIDER
20
692
192
725
hawk-hunt-speed
hawk-hunt-speed
1
25
5.0
1
1
NIL
HORIZONTAL

SLIDER
20
736
208
769
hawk-search-speed
hawk-search-speed
1
30
2.0
1
1
NIL
HORIZONTAL

SLIDER
22
782
194
815
time-to-eat
time-to-eat
1
50
10.0
1
1
NIL
HORIZONTAL

TEXTBOX
25
584
175
614
Hawk parameters
12
0.0
1

TEXTBOX
23
101
173
119
Dove parameters
12
0.0
1

SLIDER
19
242
197
275
dove-boost-speed
dove-boost-speed
1
50
1.0
1
1
NIL
HORIZONTAL

SLIDER
18
284
214
317
dove-fear-dir-noise
dove-fear-dir-noise
1
10
1.0
0.5
1
NIL
HORIZONTAL

SLIDER
19
325
191
358
dove-enemy-vision
dove-enemy-vision
1
100
1.0
1
1
NIL
HORIZONTAL

SLIDER
19
367
221
400
dove-standard-speed
dove-standard-speed
1
50
3.0
1
1
NIL
HORIZONTAL

SLIDER
21
412
206
445
threat-ignorance
threat-ignorance
0.01
1
1.0
0.01
1
NIL
HORIZONTAL

SLIDER
22
459
195
492
breeding-period
breeding-period
10
150
50.0
1
1
NIL
HORIZONTAL

CHOOSER
28
508
180
553
birth-on
birth-on
"breeding-period" "less-than-initial"
1

PLOT
1317
690
1731
970
Population by color
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -1184463 true "" "plot count doves with [color = yellow]"
"pen-1" 1.0 0 -13345367 true "" "plot count doves with [color = blue]"
"pen-2" 1.0 0 -2064490 true "" "plot count doves with [color = pink]"
"pen-3" 1.0 0 -10899396 true "" "plot count doves with [color = green]"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

bird
false
0
Polygon -7500403 true true 135 165 90 270 120 300 180 300 210 270 165 165
Rectangle -7500403 true true 120 105 180 237
Polygon -7500403 true true 135 105 120 75 105 45 121 6 167 8 207 25 257 46 180 75 165 105
Circle -16777216 true false 128 21 42
Polygon -7500403 true true 163 116 194 92 212 86 230 86 250 90 265 98 279 111 290 126 296 143 298 158 298 166 296 183 286 204 272 219 259 227 235 240 241 223 250 207 251 192 245 180 232 168 216 162 200 162 186 166 175 173 171 180
Polygon -7500403 true true 137 116 106 92 88 86 70 86 50 90 35 98 21 111 10 126 4 143 2 158 2 166 4 183 14 204 28 219 41 227 65 240 59 223 50 207 49 192 55 180 68 168 84 162 100 162 114 166 125 173 129 180

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

hawk
true
0
Polygon -7500403 true true 151 170 136 170 123 229 143 244 156 244 179 229 166 170
Polygon -16777216 true false 152 154 137 154 125 213 140 229 159 229 179 214 167 154
Polygon -7500403 true true 151 140 136 140 126 202 139 214 159 214 176 200 166 140
Polygon -16777216 true false 151 125 134 124 128 188 140 198 161 197 174 188 166 125
Polygon -7500403 true true 152 86 227 72 286 97 272 101 294 117 276 118 287 131 270 131 278 141 264 138 267 145 228 150 153 147
Polygon -7500403 true true 160 74 159 61 149 54 130 53 139 62 133 81 127 113 129 149 134 177 150 206 168 179 172 147 169 111
Circle -16777216 true false 144 55 7
Polygon -16777216 true false 129 53 135 58 139 54
Polygon -7500403 true true 148 86 73 72 14 97 28 101 6 117 24 118 13 131 30 131 22 141 36 138 33 145 72 150 147 147

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
