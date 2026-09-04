# Informe: Consultas SQL de Productividad e Inscripciones — Grupo Empresarial ESAM

## 1. Objetivo General

Este informe documenta la arquitectura y lógica de negocio aplicadas a las consultas SQL utilizadas para calcular los reportes de productividad comercial y estado de inscripciones de las distintas Unidades de Negocio del Grupo Empresarial ESAM.

El objetivo principal es estandarizar la extracción de datos en un entorno multisede, garantizando la trazabilidad financiera exacta (montos pactados, cancelados y saldos) y eliminando discrepancias por datos duplicados.

---

## 2. Contexto y Arquitectura de Datos

Las Unidades de Negocio operan de forma centralizada sobre los esquemas de base de datos MySQL `productionacademicoesamdb` y `productionadminesamdb`.

### Particularidades del Modelo Heredado
* **Jerarquía de Programas:** La relación entre un programa educativo y su categoría no es directa. La vinculación se realiza de forma jerárquica a través de la tabla intermedia de postgrados:
  `programas` -> `postgrados` -> `categorias`
* **Identificación por Sedes:** Cada Unidad de Negocio gestiona un grupo específico de sedes (`s.id`) y conceptos de pago (`pp.concepto_pago_id`), lo que requiere reglas de filtrado particulares para definir la condición de **"INSCRITO"** del alumno.

---

## 3. Patrones de Diseño SQL y Optimizaciones

### 3.1. Uso de Expresiones Comunes de Tabla (CTEs)
Las consultas utilizan CTEs (`WITH ... AS`) para aislar la lógica financiera del reporte principal. Esto mejora el rendimiento en MySQL, facilita el mantenimiento del código y previene lecturas sucias.

### 3.2. Solución al Fan-out Bug (Duplicación por Abonos Parciales)
En versiones previas del reporte, al conectar directamente `plan_pagos` con `detalle_pagos_inscripcion`, si un alumno realizaba **múltiples abonos o pagos parciales** para una misma cuota, la consulta multiplicaba las sumas agregadas (`SUM(monto)` y `SUM(saldo)`).

Para erradicar este problema, se introdujo el patrón **`cte_pagos_info`**:

```sql
cte_pagos_info AS (
    SELECT
        dpi.cuota_id,
        MAX(dpi.fecha_registro_pago) AS fecha_pago,
        MAX(pi.nro_recibo) AS nro_recibo
    FROM productionacademicoesamdb.detalle_pagos_inscripcion dpi
    INNER JOIN productionacademicoesamdb.pagos_inscripcion pi
           ON pi.id = dpi.pagos_inscripcion_id AND pi.estado = 1
    WHERE dpi.estado = 1
    GROUP BY dpi.cuota_id
)
```

Esta subconsulta agrupa estrictamente a nivel de `cuota_id`, garantizando una relación 1 a 1 antes de realizar el cálculo de los saldos y montos.

### 3.3. Estandarización del detalle financiero
Todas las consultas muestran de forma explícita el estado financiero de cada concepto relevante:
* **`MONTO`**: Suma pactada en el plan de pagos (`SUM(pp.monto)`).
* **`CANCELADO`**: Dinero efectivamente cobrado (`SUM(pp.monto - pp.saldo)`).
* **`SALDO`**: Monto pendiente de cobro (`SUM(pp.saldo)`).

---

## 4. Matriz Resumen de Reglas por Unidad de Negocio

| Unidad de Negocio | Sedes (`s.id`) | Concepto(s) Evaluado(s) | Criterio de Inscripción (`CONDICION_PRODUCTIVIDAD`) |
| :--- | :--- | :--- | :--- |
| **ESAM** | `1, 2, 3, 4, 5, 6, 7, 8, 14, 15, 16, 18, 20, 22, 23, 25, 26, 37, 50, 51, 52, 80, 125, 127, 128, 129, 132, 134` | `1` (Matrícula), `2` (Colegiatura C1), `Plan Total` | Cursos: saldo total del plan = 0; Contado: saldo colegiatura C1 = 0; Crédito: saldo matrícula = 0 AND saldo colegiatura C1 = 0 |
| **DBS** | `24, 27, 28, 29, 30, 31, 32, 33, 42, 53, 107` (Inst. `49`) | `133` (Cuota Inicial) / `2` (Colegiatura C1) | Saldo Cuota Inicial = 0 OR Saldo Colegiatura C1 = 0 |
| **UPI ESAM** | `82, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 102, 103, 104, 105, 106, 108, 109, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 126` | `1` (Matrícula), `2` (Colegiatura C1), `312` (Cuota UPI 1) | Saldo matrícula = 0 AND (Saldo colegiatura C1 OR Saldo cuota 1) = 0 |
| **ISPI** | `49` | `27` (Cuota 1 Mensualidad) | Saldo Cuota 1 Mensualidad = 0 |
| **CCA** | `9, 10, 48, 79` | `8` (Cuota 1 Mensualidades) / `17` (Cursos de formación continua) | Para cursos: saldo total del plan = 0; para carreras: saldo cuota 1 = 0 |
| **CIBERKIDS** | `11, 12, 13, 47, 81` | `27` (Cuota 1 Mensualidad) / `311` (Cursos) | Saldo = 0 (Según categoría del programa) |
| **CCTP** | `39` | `8` (Cuota 1 Mensualidades) / `18` (Cuota 1 Cursos) | Saldo Cuota 1 = 0 (Según tipo: Curso o Programa) |
| **Cyber Corp** | `21, 34, 35, 36, 40, 44, 46, 78, 83, 114, 119` | `18` (Curso CyberCorp) | Saldo total del concepto 18 = 0 |

---

## 5. Detalle de Consultas por Unidad de Negocio

---

### 5.1. ESAM

#### Objetivo Específico
Reportar las inscripciones del portafolio ESAM con una lógica financiera diferenciada según el tipo de producto, la modalidad de pago y el estado de los saldos del plan.

#### Lógica Financiera y CTEs
* `cte_matricula`: consolida el Concepto **1** (Matrícula) para evaluar el impacto de la primera obligación del plan.
* `cte_colegiatura_c1`: consolida la **Colegiatura Cuota 1** del Concepto **2** para las inscripciones con plan de pagos posgradual.
* `cte_saldo_total`: resume el saldo total del plan completo para soportar el criterio de inscripción en productos de capacitación.
* La condición de productividad cambia según el tipo de producto: cursos, planes de contado y planes de crédito.

#### Tablas Relacionadas (`JOINS`)
* `inscripciones` como tabla central hacia `programas`, `postgrados`, `categorias` y `personas`.
* `LEFT JOIN` a `plan_cobros_programa` para identificar si el plan corresponde a modalidad `Contado` o `Crédito`.
* `LEFT JOIN` a las tres CTEs financieras para calcular montos, saldos y fechas de pago por inscripción.

#### Condiciones y Filtros (`WHERE`)
* **Sedes:** `s.id IN (1, 2, 3, 4, 5, 6, 7, 8, 14, 15, 16, 18, 20, 22, 23, 25, 26, 37, 50, 51, 52, 80, 125, 127, 128, 129, 132, 134)`
* **Convenio Exclusivo:** `i2.id = 9`
* **Evaluación de Productividad:** depende del tipo de producto y del saldo asociado a matrícula o colegiatura.

---

### 5.2. DBS

#### Objetivo Específico
Reportar las inscripciones pertenecientes al convenio universitario específico (Institución ID 49).

#### Lógica Financiera y CTEs
* `cte_cuota_inicial`: Concepto **133**, Cuota 1.
* `cte_colegiatura_c1`: Concepto **2**, Cuota 1.
* `cte_saldo_total_plan`: Muestra la visión global del plan de pagos por alumno.

#### Regla de Negocio Flexible
La condición de **`INSCRITO`** se activa con un criterio incluyente: basta con que el alumno cancele la **Cuota Inicial** OR la **Primera Cuota de Colegiatura** (`saldo = 0`). La fecha de productividad toma la menor de ambas fechas registradas.

#### Condiciones y Filtros (`WHERE`)
* **Sedes:** `s.id IN (24, 27, 28, 29, 30, 31, 32, 33, 42, 53, 107)`
* **Convenio Exclusivo:** `i2.id = 49`

---

### 5.3. UPI ESAM

#### Objetivo Específico
Evaluar la productividad de las inscripciones asociadas a la unidad UPI ESAM, considerando tanto la matrícula como las primeras cuotas de colegiatura y la cuota de ingreso definida para el plan de pagos.

#### Lógica Financiera y CTEs
* `cte_matricula`: consolida el Concepto **1** (Matrícula).
* `cte_colegiatura_c1`: consolida el Concepto **2** (Colegiatura, Cuota 1).
* `cte_cuota_c1`: consolida el Concepto **312** (Cuota UPI 1) como criterio alternativo de ingreso.
* `cte_saldo_total`: resume el saldo total del plan completo para la trazabilidad financiera general.

#### Tablas Relacionadas (`JOINS`)
* `inscripciones` vinculada a `programas`, `postgrados`, `categorias` y `personas`.
* `LEFT JOIN` a las CTEs financieras para obtener montos, saldos y fechas de pago por inscripción.

#### Condiciones y Filtros (`WHERE`)
* **Sedes:** `s.id IN (82, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 102, 103, 104, 105, 106, 108, 109, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 126)`
* **Convenios Exclusivos:** `i2.id IN (301, 307)`
* **Regla de Inscripción:** se considera `INSCRITO` cuando la matrícula y la primera cuota de pago relevante están en saldo 0.

---

### 5.4. ISPI

#### Objetivo Específico
Generar el reporte de productividad de la sede ISPI basado estrictamente en el pago de la mensualidad inicial.

#### Lógica Financiera y CTEs
* `cte_mensualidad_c1`: Concepto **27**, Cuota 1.
* Determina de manera limpia el mes de productividad y la condición de inscripción del estudiante en un único flujo relacional.

#### Condiciones y Filtros (`WHERE`)
* **Sedes:** `s.id = 49`
* **Criterio de Inclusión:** Registros cuyo pago de mensualidad cuota 1 haya sido efectuado dentro del rango establecido.

---

### 5.5. CCA

#### Objetivo Específico
Gestionar la productividad de la unidad CCA diferenciando entre programas de carrera y cursos de formación continua.

#### Lógica Financiera y CTEs
* `cte_mensualidad_c1`: evalúa la **Mensualidad Cuota 1** del Concepto **8** para productos de tipo carrera.
* `cte_saldo_total`: consolida el saldo del plan completo para los cursos y los productos de formación continua usando los conceptos **8** y **17**.
* Un `CASE` basado en las categorías `c.id IN (8, 9, 10)` define si la inscripción debe evaluarse por saldo total del plan o por la mensualidad inicial.

#### Tablas Relacionadas (`JOINS`)
* `inscripciones` vinculada a catálogos de programas, postgrados, categorías y personas.
* `LEFT JOIN` a las dos CTEs financieras para calcular el estado de pago y la fecha de productividad.

#### Condiciones y Filtros (`WHERE`)
* **Sedes:** `s.id IN (9, 10, 48, 79)`
* **Regla de Inscripción:** los cursos se consideran `INSCRITO` cuando el saldo total del plan es 0; las carreras, cuando la cuota 1 mensual está cancelada.

---

### 5.6. CIBERKIDS (Sedes 11, 12, 13, 47, 81)

#### Objetivo Específico
Gestionar la productividad para unidades con oferta mixta (Talleres, Cursos, Kinder, Estimulación y Programas).

#### Lógica Financiera y CTEs
* `cte_mensualidad_c1`: Aplica el Concepto **27** (Cuota 1 Mensualidad) para las categorías `14` (Programas), `34` (Estimulación) y `35` (Kinder).
* `cte_cursos_total`: Aplica el Concepto **311** (Cursos) para las categorías `12` (Talleres) y `13` (Cursos).

#### Tablas Relacionadas (`JOINS`)
* Incluye `plan_cobros_programa` para clasificar el tipo de plan (`Contado` o `Crédito`).

#### Condiciones y Filtros (`WHERE`)
* **Sedes:** `s.id IN (11, 12, 13, 47, 81)`
* **Regla de Inscripción:** Evalúa el saldo según la categoría (`c.id`).

---

### 5.7. CCTP

#### Objetivo Específico
Reportar el estado de inscripciones diferenciando dinámicamente si la oferta corresponde a un **Curso** o a un **Programa**.

#### Lógica Financiera y CTEs
* `cte_mensualidad_c1`: Evalúa la Cuota 1 del Concepto **8** (Mensualidades).
* `cte_curso_c1`: Evalúa la Cuota 1 del Concepto **18** (Cursos).
* Un condicional `CASE` evalúa la columna `p.nombre_compuesto LIKE '%CURSO%'` para determinar qué concepto define la productividad del alumno.

#### Tablas Relacionadas (`JOINS`)
* `inscripciones` como tabla pivote hacia catálogos de programas y personas.
* `LEFT JOIN` a ambas CTEs (`mc1` y `cc1`).

#### Condiciones y Filtros (`WHERE`)
* **Sedes:** `s.id = 39`
* **Evaluación de Productividad:** Saldo = 0 en la Cuota 1 correspondiente.

---

### 5.8. Cyber Corp

#### Objetivo Específico
Evaluar la productividad de ventas exclusivamente para programas de formación continua bajo la modalidad de cursos en Cyber Corp.

#### Lógica Financiera y CTEs
Al ser una unidad enfocada únicamente en cursos cortos (Categoría 18), la consulta se simplificó a una sola CTE (`cte_pago_cybercorp`) que consolida el concepto de pago **18**.

#### Tablas Relacionadas (`JOINS`)
* `inscripciones` -> `programas` -> `postgrados` -> `categorias`
* `sedes`, `personas` (estudiante y asesor) y `unidad_negocio`

#### Condiciones y Filtros (`WHERE`)
* **Sedes:** `s.id IN (21, 34, 35, 36, 40, 44, 46, 78, 83, 114, 119)`
* **Filtro Temporal:** Rango de fecha de pago registrado en `cc.fecha_pago_productividad`.

---

## 6. Mantenimiento y Parametrización

Para ejecutar estos reportes en nuevos periodos comerciales, únicamente se debe ajustar la cláusula de fechas al final del bloque `WHERE`:

```sql
-- Ejemplo de parametrización para el Segundo Semestre 2026:
BETWEEN '2026-07-01 00:00:00' AND '2026-12-31 23:59:59'
```
