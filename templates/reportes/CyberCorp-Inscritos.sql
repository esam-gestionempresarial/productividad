WITH
-- CTE exclusiva para el Concepto de Pago 18 (CURSO CYBERCORP)
cte_pago_cybercorp AS (
    SELECT
        pp.inscripcion_id,
        SUM(pp.monto) AS monto_total,
        SUM(pp.monto - pp.saldo) AS monto_cancelado,
        SUM(pp.saldo) AS saldo_total,
        MAX(dpi.fecha_registro_pago) AS fecha_pago_productividad
    FROM productionacademicoesamdb.plan_pagos pp
    LEFT JOIN productionacademicoesamdb.detalle_pagos_inscripcion dpi
           ON dpi.cuota_id = pp.id AND dpi.estado = 1
    LEFT JOIN productionacademicoesamdb.pagos_inscripcion pi
           ON pi.id = dpi.pagos_inscripcion_id AND pi.estado = 1
    WHERE pp.concepto_pago_id = 18
    GROUP BY pp.inscripcion_id
)
SELECT
    un.nombre AS UNIDAD,
    s.nombre AS SEDE,
    CONCAT_WS(' ', p3.nombres, p3.pri_apellido, p3.seg_apellido) AS ASESOR,
    p3.num_doc AS CI_ASESOR,
    CONCAT_WS(' ', p4.nombres, p4.pri_apellido, p4.seg_apellido) AS ALUMNO,
    p4.num_doc AS CI_ALUMNO,
    c.nombre AS TIPO_PROGRAMA,
    i.id AS ID_INSCRIPCION,
    p.codigo AS COD_CONTABLE,
    p.nombre_compuesto AS PROGRAMA,
    p.id AS ID_PROGRAMA,
    -- Columnas financieras asociadas exclusivamente al concepto 18
    IFNULL(cc.monto_total, 0) AS MONTO_TOTAL,
    IFNULL(cc.monto_cancelado, 0) AS MONTO_CANCELADO,
    IFNULL(cc.saldo_total, 0) AS SALDO,
    -- Fecha de pago que rige la productividad
    cc.fecha_pago_productividad AS FECHA_PAGO_PRODUCTIVIDAD,
    -- Condición para considerar al alumno inscrito (Saldo del concepto 18 = 0)
    IF(IFNULL(cc.saldo_total, 1) = 0, 'INSCRITO', 'NO INSCRITO') AS CONDICION_PRODUCTIVIDAD,
    CASE
        WHEN i.estado_ins = 0 THEN 'PRE-INSCRITO'
        WHEN i.estado_ins = 1 THEN 'INSCRITO'
        WHEN i.estado_ins = 2 THEN 'RETIRADO'
        WHEN i.estado_ins = 3 THEN 'CAMBIADO'
        WHEN i.estado_ins = 4 THEN 'CONGELADO'
        WHEN i.estado_ins = 5 THEN 'PAGADO'
        ELSE 'NO IDENTIFICADO'
    END AS ESTADO_INSCRIPCION,
    IFNULL(i2.abreviatura, 'Sin Convenio') AS CONVENIO,
    -- Determinación del mes según fecha de productividad
    CASE MONTH(cc.fecha_pago_productividad)
        WHEN 1 THEN 'ENERO'
        WHEN 2 THEN 'FEBRERO'
        WHEN 3 THEN 'MARZO'
        WHEN 4 THEN 'ABRIL'
        WHEN 5 THEN 'MAYO'
        WHEN 6 THEN 'JUNIO'
        WHEN 7 THEN 'JULIO'
        WHEN 8 THEN 'AGOSTO'
        WHEN 9 THEN 'SEPTIEMBRE'
        WHEN 10 THEN 'OCTUBRE'
        WHEN 11 THEN 'NOVIEMBRE'
        WHEN 12 THEN 'DICIEMBRE'
    END AS MES
FROM productionacademicoesamdb.inscripciones i
INNER JOIN productionacademicoesamdb.programas p ON p.id = i.idprograma
INNER JOIN productionacademicoesamdb.postgrados p2 ON p2.id = p.idpostgrado
INNER JOIN productionacademicoesamdb.categorias c ON c.id = p2.idcategoria
INNER JOIN productionadminesamdb.personas p4 ON p4.id = i.idestudiante
LEFT JOIN  productionadminesamdb.personas p3 ON p3.id = i.idasesor
INNER JOIN productionadminesamdb.sedes s ON s.id = p.idsede
LEFT JOIN  productionadminesamdb.unidad_negocio un ON un.id = s.unidad_negocio
LEFT JOIN  productionadminesamdb.instituciones i2 ON i2.id = p.iduniversidad
-- Enlace a la CTE simplificada de Cyber Corp
LEFT JOIN cte_pago_cybercorp cc ON cc.inscripcion_id = i.id
-- Filtros de sede de Cyber Corp y rango de fechas de productividad
WHERE s.id IN (21, 34, 35, 36, 40, 44, 46, 78, 83, 114, 119)
  AND cc.fecha_pago_productividad BETWEEN '2026-01-01 00:00:00' AND '2026-06-30 23:59:59'
ORDER BY i.id;