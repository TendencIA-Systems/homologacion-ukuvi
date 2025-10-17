# Correcciones normalización

# GLOBAL

- Normalizar almacenamiento de MINI / MINI COOPER
- He visto muchos casos donde el parémetro AUT viene pegado a otros specs. Podríamos buscar casos donde AUT (no AUTO, ATOMÁTICO, etc) esté presente en una palabra y crear un espacio del resto.
- Hay que eliminar NUEVO, NUEVA LINEA y NEW de modelo
- Normalizar GENERACION y GEN. a GEN
- Si encontramos un JETTA, solo hay que guardar JETTA en el modelo y si hay más datos, los pasamos a versión.
- Eliminar PASAJEROS del modelo
- En los modelos de FORD, hay que asegurarnos de eliminar guinoes y puntos para almacenar algo como F150

## ZURICH

- Eliminar (DEBRY) de las van VW

| 7794575 | VOLKSWAGEN | VAN(DERBY) | 2003 | MANUAL | VAN
  97HP 1.8L 4CIL 3PUERTAS 3OCUP | null | null | null | null | null | null | null | null | null | null | VAN
  STD 97HP 1.8L 4CIL 3P 3OCUP | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7794578 | VOLKSWAGEN | VAN(DERBY) | 2004 | MANUAL | PTAS
  TRASERAS CON VENTANA VAN 97HP 1.8L 4CIL 3PUERTAS 3OCUP | null | null | null | null | null | null | null | null | null | null | PTAS
  TRASERAS CON VENTANA VAN STD 97HP 1.8L 4CIL 3P 3OCUP | 1 |
- Crear espacio entre modelos ELF de ISUZU

| 7784665 | ISUZU | ELF200 | 2009 | MANUAL | E
  CHASIS CABINA 138HP 3.0L 4CIL 2PUERTAS 5OCUP | null | null | null | null | null | null | null | null | null | null | E
  CHASIS CABINA STD 138HP 3L 4CIL 2P 5OCUP | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7784666 | ISUZU | ELF200 | 2010 | MANUAL | E
  CHASIS CABINA 138HP 3.0L 4CIL 2PUERTAS 5OCUP | null | null | null | null | null | null | null | null | null | null | E
  CHASIS CABINA STD 138HP 3L 4CIL 2P 5OCUP | 1 |
- Modelos de Mazda tienen marca en el modelo

```jsx
[
  {
    "idx": 4,
    "id": 5473624,
    "hash_comercial": "b5320fbbce6835410aa8994551eb8883dc820b3ecaa393367afa9fa388389d30",
    "marca": "MAZDA",
    "modelo": "MAZDA 3",
    "anio": 2006,
    "transmision": "AUTO",
    "version": "S R17 SEDAN 167HP 2.5L 4CIL 4PUERTAS 5OCUP",
    "disponibilidad": {
      "ZURICH": {
        "origen": true,
        "disponible": true,
        "aseguradora": "ZURICH",
        "id_original": 43442,
        "metodo_match": "new_entry",
        "confianza_score": 1,
        "version_original": "S R17 SEDAN AUT QC 167HP ABS 2.5L 4CIL 4P 5OCUP",
        "fecha_actualizacion": "2025-09-27T04:14:51.181Z"
      }
    }
  }
]
```

## QUALITAS

- Agregar guión a modelos de MERCEDES BENZ

| 7804744 | MERCEDES BENZ | C 250 | 2012 | AUTO | CGI COUPE CONFORT C A 5OCUP | null | null | null | null | null | null | null | null | null | CGI COUPE CONFORT C/A SNAV BA ABS
  AUT., 05 OCUP. | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- Crear espacio entre modelos SEI de JAC, mismo con ESEI

| 7784779 | JAC | SEI3 | 2019 | AUTO | LIMITED SUV 118HP 1.6L 4CIL 5PUERTAS
  5OCUP | null | JAC SEI3 CROSSOVER 1.6L AUT | null | null | null | null | null | null | null | LIMITED 5P L4 1.6L R16 CVT 5 OCUP | CONNECT SUV AUT AA EE CD BA 118HP ABS
  1.6L 4CIL 5P 5OCUP | 3 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7840498 | JAC | SEI3 | 2019 | AUTO | QUANTUM 1.6L | null | JAC SEI3 QUANTUM 1.6L AUT | null | null | null | null | null | null | null | null | null | 1 |
| 7784780 | JAC | SEI3 | 2019 | MANUAL | QUANTUM
  SUV 116HP 1.6L 4CIL 5PUERTAS 5OCUP | null | JAC
  SEI3 CROSSOVER 1.6L STD | null | null | null | null | null | null | null | LIMITED
  5P L4 1.6L R16 STD 5 OCUP | CONNECT
  SUV STD AA EE CD BA 118HP ABS 1.6L 4CIL 5P 5OCUP | 3 |
- Eliminar PASAJEROS de las van de VW

| 7812208 | VOLKSWAGEN | VAN
  PASAJEROS | 2004 | MANUAL | 5OCUP | null | null | null | null | null | null | null | null | null | C/A
  AC STD., 05 OCUP. | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7812208 | VOLKSWAGEN | VAN
  PASAJEROS | 2004 | MANUAL | 5OCUP | null | null | null | null | null | null | null | null | null | C/A
  AC STD., 05 OCUP. | null | 1 |

## CHUBB

- Asegurar que no queden espacios entre specs de cilindrada

```jsx
[
  {
    "idx": 28,
    "id": 5633147,
    "hash_comercial": "7be2838cb297e701d846c06aefc882a29d9014917f0cabffc86f4616bb008552",
    "marca": "ACURA",
    "modelo": "ILX",
    "anio": 2016,
    "transmision": "AUTO",
    "version": "TECH 2.0LAUT 4 CIL 4PUERTAS 5OCUP",
    "disponibilidad": {
      "ELPOTOSI": {
        "origen": true,
        "disponible": true,
        "aseguradora": "ELPOTOSI",
        "id_original": 48245,
        "metodo_match": "new_entry",
        "confianza_score": 1,
        "version_original": "TECH 2.0LAUT 4 PTAS 5 OCUP , 4 CIL, ABS, A/A, E/E, PIEL, B/A",
        "fecha_actualizacion": "2025-09-27T04:47:29.744Z"
      }
    }
  }
]
```

- Eliminar HYUNDAI del modelo, igual con HONDA

| 7818376 | HYUNDAI | PICK UP HYUNDAI | 2004 | MANUAL | H 1.2.5L TURBO 4CIL D T SA SE SS SB
  2PUERTAS | null | null | null | null | H 100 1.25T L4  STD 2 D/T SA SE  SS 
  SB | null | null | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7818229 | HONDA | PICK
  UP HONDA | 2009 | AUTO | RIDGELINE
  .75T 6CIL 4PUERTAS | null | null | null | null | RIDGELINE
  .75T V6  AUT 4 ABS CA CE  CD 
  CB | null | null | null | null | null | null | 1 |
- Limpiar Marca del campo Modelo

```jsx
[
  {
    "idx": 153,
    "id": 5538850,
    "hash_comercial": "034af467409ef6c2d178718b794710a99b2c508a054686b44e0920790b656089",
    "marca": "NISSAN",
    "modelo": "PICK UP NISSAN",
    "anio": 2017,
    "transmision": "MANUAL",
    "version": "DH EDICION ESPECIAL 4CIL DIS SA SE SS 2PUERTAS",
    "disponibilidad": {
      "CHUBB": {
        "origen": true,
        "disponible": true,
        "aseguradora": "CHUBB",
        "id_original": 4108,
        "metodo_match": "new_entry",
        "confianza_score": 1,
        "version_original": "DH EDICION ESPECIAL L4  STD 2 DIS SA SE TELA SS",
        "fecha_actualizacion": "2025-09-27T04:19:46.319Z"
      }
    }
  }
]
```

## ANA

- Modelos de Mazda tienen marca (Ma) en el modelo

```jsx
[
  {
    "idx": 7,
    "id": 5555528,
    "hash_comercial": "08d7826c15282a6da8df86b707d4890d974fb3c23179f1f2fd5e50cbea49da1e",
    "marca": "MAZDA",
    "modelo": "MA 3",
    "anio": 2009,
    "transmision": "MANUAL",
    "version": "I 2.0L 4PUERTAS",
    "disponibilidad": {
      "ANA": {
        "origen": true,
        "disponible": true,
        "aseguradora": "ANA",
        "id_original": 38546,
        "metodo_match": "new_entry",
        "confianza_score": 1,
        "version_original": "I 2.0L ESTANDAR 4PTAS",
        "fecha_actualizacion": "2025-09-27T04:21:52.955Z"
      }
    }
  }
]
```

- Eliinar 4XE del modelo y agregarlo a la versión
- Limpiar correctamente el modelo contaminado

| 7833000 | VOLKSWAGEN | POINTER PICK-UP | 2007 | AUTO | COMFORTLINE DH ES | COMFORTLINE AC DH ES | null | null | null | null | null | null | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7833001 | VOLKSWAGEN | POINTER PICK-UP | 2007 | MANUAL | DH LUJO EST | AC VE DH RA LUJO EST | null | null | null | null | null | null | null | null | null | null | 1 |
| 7829352 | MERCEDES BENZ | ESTACAS 7.5 TON | 2014 | AUTO | AMG 2PUERTAS | 63 AMG AUTOMATICA 2PTAS | null | null | null | null | null | null | null | null | null | null | 1 |
| 7829361 | MERCEDES BENZ | ESTACAS 7.5 TON | 2014 | AUTO | CGI EXCLISIVE AU 200PUERTAS | 200 CGI EXCLISIVE NAVI AU | null | null | null | null | null | null | null | null | null | null | 1 |

## ATLAS

- Eliminar Marca JAC del modelo.
- Crear espacio entre modelos SEI de JAC, mismo con ESEI

| 7784779 | JAC | SEI3 | 2019 | AUTO | LIMITED SUV 118HP 1.6L 4CIL 5PUERTAS
  5OCUP | null | JAC SEI3 CROSSOVER 1.6L AUT | null | null | null | null | null | null | null | LIMITED 5P L4 1.6L R16 CVT 5 OCUP | CONNECT SUV AUT AA EE CD BA 118HP ABS
  1.6L 4CIL 5P 5OCUP | 3 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7840498 | JAC | SEI3 | 2019 | AUTO | QUANTUM 1.6L | null | JAC SEI3 QUANTUM 1.6L AUT | null | null | null | null | null | null | null | null | null | 1 |
| 7784780 | JAC | SEI3 | 2019 | MANUAL | QUANTUM
  SUV 116HP 1.6L 4CIL 5PUERTAS 5OCUP | null | JAC
  SEI3 CROSSOVER 1.6L STD | null | null | null | null | null | null | null | LIMITED
  5P L4 1.6L R16 STD 5 OCUP | CONNECT
  SUV STD AA EE CD BA 118HP ABS 1.6L 4CIL 5P 5OCUP | 3 |
- Eliminar KIA de la versión

| 7840550 | KIA
  MOTORS | EV6 | 2024 | AUTO | KIA
  GT | null | KIA
  EV6 GT LINE AUT | null | null | null | null | null | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- Eliminar VW de la versión

| 7845982 | VOLKSWAGEN | JETTA
  MKVI | 2018 | MANUAL | VW
  SPORTLINE | null | VW
  JETTA MKVI SPORTLINE STD | null | null | null | null | null | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7845976 | VOLKSWAGEN | JETTA
  MKVI | 2018 | MANUAL | VW
  2.0L 115HP | null | VW
  JETTA MKVI 2.0L 115HP STD | null | null | null | null | null | null | null | null | null | 1 |
- Cambiar Marca a GENERAL MOTORS a GM
- Limpiar modelo, el siguiente caso muestra tonelaje

| 7841375 | MERCEDES BENZ | CLASE A AMG | 2021 | AUTO | 35 AMG 4CIL 4PUERTAS | null | MERCEDES BENZ A 35 AMG 4PTAS L4 AUT | null | null | null | null | null | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7841376 | MERCEDES BENZ | CLASE A AMG | 2021 | AUTO | CLASE 45 AMG S AWD 45PUERTAS | null | MERCEDES BENZ CLASE A 45 AMG S
  4MATIC DCT | null | null | null | null | null | null | null | null | null | 1 |
- Eliminar NUEVO del modelo.

| 7846735 | VOLVO | NUEVO
  V40 | 2017 | AUTO | V40
  T5 R DESIGN 213HP | null | VOLVO
  V40 T5 R-DESIGN 213HP AUT | null | null | null | null | null | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7846733 | VOLVO | NUEVO
  V40 | 2017 | AUTO | V40
  CROSS COUNTRY MOMENTUM 1.6L | null | VOLVO
  V40 CROSS COUNTRY INSPIRATION AUT | null | null | null | null | null | null | null | null | null | 1 |

## AXA

- Agregar guión medio a los T CROSS (T-CROSS)

| 7849451 | VOLKSWAGEN | T
  CROSS | 2020 | AUTO | HIGHLINE
  4CIL 5PUERTAS | null | null | COMFORTLINE
  AUT 5P 4CIL | null | null | null | VOLKSWAGEN
  T CROSS HIGHLINE L4 1.6 TIPTRONIC | null | null | null | null | 2 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7849450 | VOLKSWAGEN | T
  CROSS | 2020 | MANUAL | TRENDLINE
  EDICION LANZAMIENTO 4CIL 5PUERTAS | null | null | TRENDLINE
  STD 5P 4CIL | null | null | null | VOLKSWAGEN
  T CROSS TRENDLINE L4 1.6 STD | null | null | null | null | 2 |

## BX

- En modelos de volvo, hay que eliminar el espacio

| 7862222 | VOLVO | XC
  60 | 2009 | AUTO | 3.2L
  6CIL AWD 285HP 7OCUP | null | null | null | 3.2L
  V6 AWD 285HP AUT. 07 OCUP. | null | null | null | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7862223 | VOLVO | XC
  60 | 2010 | AUTO | 3.2L
  6CIL AWD 285HP 7OCUP | null | null | null | 3.2L
  V6 AWD 285HP AUT. 07 OCUP. | null | KINETIC
  3.2 AWD Aut 0 Ton 5 Ocup 4 ptas V6 | null | null | null | null | null | 2 |
- Modelos de Mazda tienen marca en el modelo

```jsx
[
  {
    "idx": 7,
    "id": 5620981,
    "hash_comercial": "3d690e131c893376111dbe0f3fd57c6b3124eec29eea462ce1739eacd855d55f",
    "marca": "MAZDA",
    "modelo": "MAZDA 3",
    "anio": 2006,
    "transmision": "MANUAL",
    "version": "HATCHBACK S 2.3L 5CIL",
    "disponibilidad": {
      "BX": {
        "origen": true,
        "disponible": true,
        "aseguradora": "BX",
        "id_original": 108173,
        "metodo_match": "inclusion_index",
        "confianza_score": 1,
        "version_original": "S 2.3L 5V STD. CD",
        "fecha_actualizacion": "2025-09-27T04:45:08.961Z"
      }
    }
]
```

## EL POTOSI

- En modelos de volvo, hay que eliminar el espacio

| 7862222 | VOLVO | XC
  60 | 2009 | AUTO | 3.2L
  6CIL AWD 285HP 7OCUP | null | null | null | 3.2L
  V6 AWD 285HP AUT. 07 OCUP. | null | null | null | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7862223 | VOLVO | XC
  60 | 2010 | AUTO | 3.2L
  6CIL AWD 285HP 7OCUP | null | null | null | 3.2L
  V6 AWD 285HP AUT. 07 OCUP. | null | KINETIC
  3.2 AWD Aut 0 Ton 5 Ocup 4 ptas V6 | null | null | null | null | null | 2 |
- Modelos de Mazda tienen marca en el modelo

```jsx
[
  {
    "idx": 443,
    "id": 5644130,
    "hash_comercial": "9b0911f70a8ee2bc4235180735461b3835cca00e32b19541c6054b9dc5677eb7",
    "marca": "MAZDA",
    "modelo": "MAZDA 2",
    "anio": 2022,
    "transmision": "AUTO",
    "version": "IA T 0TON OCUP 4CIL 4PUERTAS",
    "disponibilidad": {
      "ELPOTOSI": {
        "origen": true,
        "disponible": true,
        "aseguradora": "ELPOTOSI",
        "id_original": 45931,
        "metodo_match": "new_entry",
        "confianza_score": 1,
        "version_original": "IA T/A A 0 TON OCUP 4 PTAS L4 ABS CA CE TELA CD SQ CB",
        "fecha_actualizacion": "2025-09-27T04:48:37.326Z"
      }
    }
]
```

- Eliminar JAGUAR (marca) del modelo

| 7864723 | JAGUAR | JAGUAR
  F- TYPE | 2016 | AUTO | F
  TYPE-S COUPE V6AUT 6 CIL 2PUERTAS 4OCUP | null | null | null | null | null | F-
  TYPE S COUPE V6AUT 2 PTAS 4 OCUP , 6 CIL, ABS, A/A, E/E, PIEL, Q/C, B/A | null | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- Modelos de Mercedez Benz tienen MERCEDEZ en Modelo

```jsx
[
  {
    "idx": 305,
    "id": 5644806,
    "hash_comercial": "049da728ab9acde82841847ec4ac04aca147fa073dddaf8199406f0b4f2e4abd",
    "marca": "MERCEDES BENZ",
    "modelo": "MERCEDES CLASE E",
    "anio": 2021,
    "transmision": "AUTO",
    "version": "200 CGI AVANTGARDEAUT 4 CIL 4PUERTAS 5OCUP",
    "disponibilidad": {
      "ELPOTOSI": {
        "origen": true,
        "disponible": true,
        "aseguradora": "ELPOTOSI",
        "id_original": 47334,
        "metodo_match": "new_entry",
        "confianza_score": 1,
        "version_original": "200 CGI AVANTGARDEAUT 4 PTAS 5 OCUP , 4 CIL, ABS, A/A, E/E, TELA, B/A",
        "fecha_actualizacion": "2025-09-27T04:48:42.154Z"
      }
    }
  }
]
```

## GNP

- Eliminar VW de la version

| 7883206 | VOLKSWAGEN | T
  CROSS | 2020 | MANUAL | VW
  TREND LANZAMIENTO 4CIL 1.6L | null | null | null | null | null | null | VW
  T CROSS TREND LANZAMIENTO L4 1.6 STD | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- Agregar guión medio a los T CROSS (T-CROSS)

| 7849451 | VOLKSWAGEN | T
  CROSS | 2020 | AUTO | HIGHLINE
  4CIL 5PUERTAS | null | null | COMFORTLINE
  AUT 5P 4CIL | null | null | null | VOLKSWAGEN
  T CROSS HIGHLINE L4 1.6 TIPTRONIC | null | null | null | null | 2 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7849450 | VOLKSWAGEN | T
  CROSS | 2020 | MANUAL | TRENDLINE
  EDICION LANZAMIENTO 4CIL 5PUERTAS | null | null | TRENDLINE
  STD 5P 4CIL | null | null | null | VOLKSWAGEN
  T CROSS TRENDLINE L4 1.6 STD | null | null | null | null | 2 |
- Hay que limpiar correctamente el campo Modelo

| 7881378 | VOLKSWAGEN | TERAMONT COMFORTLINE | 2000 | AUTO | PANEL BANCA CORRIDA | null | null | null | null | null | null | VOLKSWAGEN PANEL BANCA CORRIDA | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7881381 | VOLKSWAGEN | TERAMONT COMFORTLINE | 2001 | AUTO | PANEL BANCA CORRIDA | null | null | null | null | null | null | VOLKSWAGEN PANEL BANCA CORRIDA | null | null | null | null | 1 |
- Eliminar HYUNDAI del modelo

| 7884267 | HYUNDAI | HYUNDAI HB20 | 2023 | AUTO | HATCHBACK 20 GL 4CIL 1.6L 20PUERTAS | null | null | null | null | null | null | HYUNDAI HB20 GL L4 1.6 AUT                         | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- Eliminar GWM (marca) de la versión

| 7884219 | GREAT
  WALL MOTORS | HAVAL
  H6 | 2024 | AUTO | GWM
  HAVAL 6CIL PREMIUM 1.5L HEV | null | null | null | null | null | null | GWM
  HAVAL H6 PREMIUM 1.5 HEV AUT | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- Eliminar GENERAL MOTORS del modelo

| 7881986 | GMC | GENERAL
  MOTORS CAMARO | 2022 | AUTO | CAMARO
  ZL 1 6.2L 8CIL CONVERTIBLE 1PUERTAS | null | null | null | null | null | null | CAMARO
  ZL1 6.2 V8 CONVERTIBLE AUT | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- Eliminar DODGE del modelo

| 7870083 | CHRYSLER | DODGE
  ATTITUDE | 2015 | AUTO | SE
  4CIL 1.2L | null | null | null | null | null | null | DODGE
  ATTITUDE SXT L4 1.2 AUT | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7881857 | CHRYSLER | DODGE
  ATTITUDE | 2015 | AUTO | ATTITUDE
  SXT 3CIL 1.2L | null | null | null | null | null | null | DODGE
  ATTITUDE SE L3 1.2 AUT | null | null | null | null | 1 |
- Hay que asegurarnos de limpiar correctamente la Marca y Modelo del campo Version

```jsx
[
  {
    "idx": 33,
    "id": 5655008,
    "hash_comercial": "03113234aca4476fb2e7ebe3a832468d6755dd1c4b438604f85eddc59fd67112",
    "marca": "AUDI",
    "modelo": "Q7",
    "anio": 2012,
    "transmision": "AUTO",
    "version": "7 S-LINE 8CIL 4.2L AWD DIESEL_TURBO 7PUERTAS",
    "disponibilidad": {
      "GNP": {
        "origen": true,
        "disponible": true,
        "aseguradora": "GNP",
        "id_original": 4582012,
        "metodo_match": "new_entry",
        "confianza_score": 1,
        "version_original": "AUDI Q7 SLINE V8 4.2L TIPTRONIC QUATTRO TDI",
        "fecha_actualizacion": "2025-09-27T04:50:32.504Z"
      }
    }
  }
]
```

## HDI

- Agregar guión a modelos de MERCEDES BENZ

| 7888845 | MERCEDES
  BENZ | C
  180 | 2017 | MANUAL | CGI
  SEDAN | null | null | null | null | null | null | null | CGI
  SEDAN STD | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- Eliminar PASAJEROS de los TRANSPORTER de VW

| 7891453 | VOLKSWAGEN | TRANSPORTER PASAJEROS | 2011 | MANUAL | TD BANCA CORRIDA DH | null | null | null | null | null | null | null | TD STD BANCA CORRIDA BA DH | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7891453 | VOLKSWAGEN | TRANSPORTER PASAJEROS | 2011 | MANUAL | TD BANCA CORRIDA DH | null | null | null | null | null | null | null | TD STD BANCA CORRIDA BA DH | null | null | null | 1 |
- Eliminar MAZDA de los modelos

| 7888684 | MAZDA | MAZDA3 | 2016 | AUTO | I
  TOURING 4CIL 2.0L 155HP 4PUERTAS | null | null | null | null | null | null | null | S,
  L4, 2.5L, 188 CP, 4 PUERTAS, AUT | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- En los volvos, hay que eliminar los guiones del modelo

| 7891611 | VOLVO | XC-90 | 2013 | AUTO | RD
  6CIL 3.2L | null | null | null | null | null | null | null | RD  L6/3.2/ AUT | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7891612 | VOLVO | XC-90 | 2016 | AUTO | INCRIPTON
  BY DESIGNER T 6 4CIL 2.0L TURBO 6PUERTAS | null | null | null | null | null | null | null | INCRIPTON
  BY DESIGNER T6 L4/2.0/T AUT | null | null | null | 1 |
- Modelos de Mazda tienen marca en el modelo

```jsx
[
  {
    "idx": 650,
    "id": 5691708,
    "hash_comercial": "c76f0ba413fb4c705a9cf877bf0fbe86707ede1abcbdd3ff6d67623ac8b9c3a7",
    "marca": "MAZDA",
    "modelo": "MAZDA2",
    "anio": 2018,
    "transmision": "AUTO",
    "version": "I TOURING 4CIL 1.5L 106HP 5PUERTAS",
    "disponibilidad": {
      "HDI": {
        "origen": true,
        "disponible": true,
        "aseguradora": "HDI",
        "id_original": 92557,
        "metodo_match": "inclusion_index",
        "confianza_score": 1,
        "version_original": "I, L4, 1.5L, 106 CP, 5 PUERTAS, AUT",
        "fecha_actualizacion": "2025-09-27T04:56:57.533Z"
      }
    }
]
```

- Puede contener specs adicionales en el modelo
    
    ```jsx
    [
      {
        "idx": 667,
        "id": 5691437,
        "hash_comercial": "9b059b84a4ed5e32a76b33fbfdd8cee6922afc57a7dc2cee0c1f844ac58757ae",
        "marca": "MAZDA",
        "modelo": "3 S",
        "anio": 2009,
        "transmision": "MANUAL",
        "version": "SEDAN",
        "disponibilidad": {
          "HDI": {
            "origen": true,
            "disponible": true,
            "aseguradora": "HDI",
            "id_original": 92669,
            "metodo_match": "new_entry",
            "confianza_score": 1,
            "version_original": "SEDAN STD",
            "fecha_actualizacion": "2025-09-27T04:56:52.221Z"
          }
        }
      },
      {
        "idx": 668,
        "id": 5691384,
        "hash_comercial": "d850c94e6797302c652d4c22895cb8944c6aa7ba07b4b5d70fe2de5ba0573481",
        "marca": "MAZDA",
        "modelo": "2 HATCHBACK",
        "anio": 2016,
        "transmision": "MANUAL",
        "version": "I TOURING",
        "disponibilidad": {
          "HDI": {
            "origen": true,
            "disponible": true,
            "aseguradora": "HDI",
            "id_original": 92540,
            "metodo_match": "new_entry",
            "confianza_score": 1,
            "version_original": "I TOURING STD",
            "fecha_actualizacion": "2025-09-27T04:56:52.221Z"
          }
        }
      }
    ]
    ```
    

## MAPFRE

- Nueva estrategia para limipieza de modelo. Habr[ia que diseñar una nueva estrategia para extraer los specs de ambos campos para los specs para el campo Version y normalizar el campo Modelo.
- Cambiar Marca CHRYSLER-DODGE y CHRYSLER-DODGE DG a CHRYSLER

```jsx
[
  {
    "idx": 934,
    "id": 5571951,
    "hash_comercial": "02f52a2b33d51b10f60577cb6c24b32ae4cb86224cc6b73df9cdebd0f0267598",
    "marca": "CHRYSLER-DODGE DG",
    "modelo": "JEEP CHEROKEE OVERLAND V6 4X2 TA",
    "anio": 2020,
    "transmision": "AUTO",
    "version": "OVERLAND V6 4",
    "disponibilidad": {
      "MAPFRE": {
        "origen": true,
        "disponible": true,
        "aseguradora": "MAPFRE",
        "id_original": 92,
        "metodo_match": "new_entry",
        "confianza_score": 1,
        "version_original": "OVERLAND V6 4TA",
        "fecha_actualizacion": "2025-09-27T04:24:03.444Z"
      }
    }
  }
]
```

- Eliminar GM de la marca CHEVROLET

| 7896938 | CHEVROLET GM | ACADIA | 2021 | AUTO | DENALI 3.6L | null | null | null | null | null | null | null | null | DENALI 3.6L TA | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7896929 | CHEVROLET GM | ACADIA | 2021 | AUTO | BLACK EDITION 3.6L | null | null | null | null | null | null | null | null | BLACK EDITION 3.6L TA | null | null | 1 |
- Revisar y limpiar entradas de BMW. Una de las cosas a hacer es eliminar BW de la marca

```jsx
[
  {
    "idx": 21,
    "id": 5566750,
    "hash_comercial": "00e5a9d73ec4378c61be1ceae99f5af27c288777a5592b3b04b9bb2fa32e1900",
    "marca": "BMW BW",
    "modelo": "SERIE 4",
    "anio": 2021,
    "transmision": "AUTO",
    "version": "430",
    "disponibilidad": {
      "MAPFRE": {
        "origen": true,
        "disponible": true,
        "aseguradora": "MAPFRE",
        "id_original": 319,
        "metodo_match": "new_entry",
        "confianza_score": 1,
        "version_original": "430I TA",
        "fecha_actualizacion": "2025-09-27T04:23:41.343Z"
      }
    }
  }
]
```

- Eliminar VW de VOLKSWAGEN

```jsx
[
  {
    "idx": 889,
    "id": 5581219,
    "hash_comercial": "00b3eee7ada823f570d0ba12c4c013610756c8450e3f18605a1e96a59d44ede2",
    "marca": "VOLKSWAGEN VW",
    "modelo": "GTI",
    "anio": 2016,
    "transmision": "FENDER DSG ASISTENTE",
    "version": "FENDER ASISTENTE",
    "disponibilidad": {
      "MAPFRE": {
        "origen": true,
        "disponible": true,
        "aseguradora": "MAPFRE",
        "id_original": 318,
        "metodo_match": "new_entry",
        "confianza_score": 1,
        "version_original": "FENDER DSG ASISTENTE",
        "fecha_actualizacion": "2025-09-27T04:25:03.985Z"
      }
    }
  }
]
```

- Reemplazar Marca CHEVROLET GM por GENERAL MOTORS

```jsx
[
  {
    "idx": 738,
    "id": 5570171,
    "hash_comercial": "00795c22a378dc0e856786f4acadf929831099eefd86405e1afd3de2c84ab94b",
    "marca": "CHEVROLET GM",
    "modelo": "CAVALIER",
    "anio": 2019,
    "transmision": "AUTO",
    "version": "PREMIER 4PUERTAS",
    "disponibilidad": {
      "MAPFRE": {
        "origen": true,
        "disponible": true,
        "aseguradora": "MAPFRE",
        "id_original": 363,
        "metodo_match": "new_entry",
        "confianza_score": 1,
        "version_original": "PREMIER 4 PTS TA C",
        "fecha_actualizacion": "2025-09-27T04:23:57.948Z"
      }
    }
  }
]
```

- Mover el número de los mercedez benz que están al principio de la versión, y egregarlo al modelo con un guión (C-200)

| 7901487 | MERCEDES
  BENZ | C | 2023 | AUTO | 200
  CGI SPORT | null | null | null | null | null | null | null | null | C
  200 CGI SPORT | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7901547 | MERCEDES
  BENZ | C | 2023 | AUTO | 43
  4 MATIC AMG | null | null | null | null | null | null | null | null | C
  43  4MATIC | null | null | 1 |
| 7901562 | MERCEDES BENZ | C | 2024 | MANUAL | 63 SE PERFORMANCE HEV AMG | null | null | null | null | null | null | null | null | C 63  SE PERFORMANCE HEV | null | null | 1 |

### HDI, QUALITAS y ZURICH

- En modelos de Chrysler, crear un espacio para que se vea como “300 C”

| 7781153 | CHRYSLER | 300C | 2007 | AUTO | SEDAN
  250HP 3.5L 6CIL 4PUERTAS 5OCUP | null | null | null | null | null | null | null | BASE,
  V6, 3.5L, 250 CP, 4 PUERTAS, AUT, PIEL | null | V/P
  AUT., 05 OCUP. | SEDAN
  AUT VP 250HP ABS 3.5L 6CIL 4P 5OCUP | 3 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7781155 | CHRYSLER | 300C | 2007 | AUTO | HERITAJE
  EDITION II R16 SEDAN 360HP 5.7L 8CIL 4PUERTAS 5OCUP | null | null | null | null | null | null | null | SRT,
  V8, 5.7L, 340 CP, 4 PUERTAS, AUT, PIEL | null | V/P
  AUT., 05 OCUP. | SRT
  SEDAN AUT QC VP 425HP ABS 6.1L 8CIL 4P 5OCUP | 3 |

## MINI COOPER

Hay que normalizar para que en marca se almacene BMW y en modelo MINI COOPER

- ANA

| 7806551 | MINI | COOPER | 2006 | MANUAL | PARK LANE 4OCUP | PARK LANE VP QC ESTANDAR 2PTAS | MINI COOPER S PARK LANE STD | null | null | null | null | null | null | null | "S" PARK LANE STD., 04 OCUP. | null | 3 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- ATLAS

| 7842360 | MINI | COOPER | 2002 | MANUAL | 115HP CHILI | null | MINI COOPER 115HP CHILI STD | null | null | null | null | null | null | null | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- AXA

| 7829702 | MINI | COOPER | 2006 | MANUAL | SEVEN 2PUERTAS | PARK LANE VP QC ESTANDAR 2PTAS | null | S CHILI STD 2P 4CIL | null | null | null | null | null | null | null | null | 2 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- BX (correcto)
- CHUBB (correcto)
- EL POTOSI (correcto)
- GNP (correcto)
- HDI (correcto)
- MAPFRE

| 7893021 | BMW | MINI | 2002 | AUTO | CHILI HOT COOPER | null | null | null | null | null | null | null | null | CHILI TELA | null | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7893120 | BMW | MINI | 2002 | AUTO | COPPER SALT SUPERCARGADO | null | null | null | null | null | null | null | null | MINI COPPER SALT SUPERCARGADO | null | null | 1 |
| 7893135 | BMW | MINICOOPER | 2011 | MANUAL | MINI
  HOTCHILI | null | null | null | null | null | null | null | null | MINI
  C MAN S HOTCHILI  TA | null | null | 1 |
- QUALITAS (También identifico que hay que eliminar las comillas dobles)

| 7806529 | MINI | COOPER | 2003 | MANUAL | "S" SALT 6VEL V T 4OCUP | null | null | null | null | null | null | null | null | null | "S" CHILI 6VEL V/P Q/C STD., 04 OCUP. | null | 1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
- ZURICH

(Almacena MINI en marca, MINI COOPER en modelo) ZURICH,54364,MINI,*MINI COOPER,*2000,HB STD VP 122HP 1.6L 4CIL 3P 5OCUP,MANUAL,1