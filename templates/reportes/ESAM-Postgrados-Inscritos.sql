USE productionacademicoesamdb;

SELECT
    un.nombre AS UNIDAD,
    s.nombre AS SEDE,
    CONCAT_WS(' ', p3.nombres, p3.pri_apellido, p3.seg_apellido) AS ASESOR,
    p3.num_doc AS CI_ASESOR,
    i.id AS ID_INSCRIPCION,
    CONCAT_WS(' ', p4.pri_apellido, p4.seg_apellido, p4.nombres) AS ALUMNO,
    p4.num_doc AS CI_ALUMNO,
    c.nombre AS TIPO,
    IFNULL(p.codigo, 'sin definir') AS COD_CONTABLE,
    p.nombre_compuesto AS PROGRAMA,
    IF(MAX(kardex.es_contado) = 1, 'Contado', 'Crédito') AS TIPO_PLAN_PAGO,
    IFNULL(MAX(kardex.nro_cuota), 0) AS NRO_CUOTAS,
    IFNULL(SUM(CASE WHEN kardex.concepto_pago_id = 1 THEN kardex.pagado ELSE 0 END), 0) AS PAGO_MATRICULA,
    IFNULL(SUM(CASE WHEN kardex.concepto_pago_id = 2 THEN kardex.pagado ELSE 0 END), 0) AS PAGO_COLEGIATURA,
    IFNULL(SUM(kardex.monto), 0) AS MONTO_TOTAL,
    DATE(IFNULL(MIN(kardex.fecha_pago_min), '1900-01-01')) AS FECHA_PAGO_1RA_CUOTA,
    /* ── Estado Esam Real ── */
    CASE
        WHEN ei.id IN (0,1,2,3,4,5) AND SUM(kardex.total_formativo_cuota) = 0  THEN 'Prospecto'
        WHEN ei.nombre = 'Retirado' AND SUM(kardex.total_formativo_cuota) <  (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Retirado Preinscrito'
        WHEN ei.nombre = 'Retirado' AND SUM(kardex.total_formativo_cuota) >= (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Retirado Inscrito'
        WHEN ei.nombre = 'Cambiado' AND SUM(kardex.total_formativo_cuota) <  (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Cambiado Preinscrito'
        WHEN ei.nombre = 'Cambiado' AND SUM(kardex.total_formativo_cuota) >= (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Cambiado Inscrito'
        WHEN ei.id IN (0,1,4,5) AND SUM(kardex.total_formativo_cuota) <  (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Preinscrito'
        WHEN ei.id IN (0,1) AND SUM(kardex.total_formativo_cuota) >= (CASE WHEN c.nombre = 'Diplomado' THEN 600 ELSE 800 END) THEN 'Inscrito'
        ELSE IFNULL(ei.nombre, 'sin definir')
    END AS ESTADO_ESAM_REAL,
    IFNULL(SUM(kardex.pagado), 0) AS MONTO_CANCELADO,
    IFNULL(SUM(kardex.saldo), 0) AS SALDO,
    IFNULL(i2.abreviatura, 'Sin convenio') AS CONVENIO
FROM inscripciones i
LEFT JOIN productionadminesamdb.personas p3 ON i.idasesor = p3.id
INNER JOIN productionadminesamdb.personas p4 ON i.idestudiante = p4.id
INNER JOIN programas p ON p.id = i.idprograma
INNER JOIN postgrados p2 ON p2.id = p.idpostgrado
INNER JOIN categorias c ON c.id = p2.idcategoria
INNER JOIN productionadminesamdb.sedes s ON s.id = p.idsede
LEFT JOIN productionadminesamdb.unidad_negocio un ON s.unidad_negocio = un.id
INNER JOIN estados_inscripcion ei ON ei.id = i.estado_ins
LEFT JOIN productionadminesamdb.instituciones i2 ON p.iduniversidad = i2.id
/* ════════════════════════════════════════════════════
   SUBQUERY KARDEX LIGERO
   ════════════════════════════════════════════════════ */
LEFT JOIN (
    SELECT
        plan_actualizado.id,
        plan_actualizado.nro_cuota,
        plan_actualizado.concepto_pago_id,
        plan_actualizado.inscripcion_id,
        plan_actualizado.monto,
        SUM(IFNULL(dpi.monto, 0)) AS pagado,
        (plan_actualizado.monto - plan_actualizado.descuento - SUM(IFNULL(dpi.monto, 0))) AS saldo,
        IF(UPPER(plan_actualizado.plan_pago) LIKE '%CONTADO%', 1, 0) AS es_contado,
        CASE 
            WHEN plan_actualizado.concepto_pago_id IN (1,2) 
            THEN IFNULL(SUM(IFNULL(dpi.monto,0)), 0) + IFNULL(plan_actualizado.monto_regularizado, 0) + IFNULL(plan_actualizado.monto_compensacion, 0) 
            ELSE 0 
        END AS total_formativo_cuota,
        MIN(dpi.fecha_registro_pago) AS fecha_pago_min
    FROM (
        SELECT
            pp.id,
            pp.nro_cuota,
            pp.concepto_pago_id,
            pp.inscripcion_id,
            pcp.nombre AS plan_pago,
            pp.monto,
            SUM(IF(m.tipo_descuento_id = 1, ppd.monto, 0)) AS monto_regularizado,
            SUM(IF(m.tipo_descuento_id = 4, ppd.monto, 0)) AS monto_compensacion,
            SUM(IFNULL(ppd.monto, 0)) AS descuento
        FROM plan_pagos pp
        JOIN inscripciones i ON pp.inscripcion_id = i.id
        JOIN plan_cobros_programa pcp ON pcp.id = i.plan_cobro_programa_id
        LEFT JOIN plan_pago_descuento ppd ON pp.id = ppd.plan_pago_id AND ppd.fecha_registro < CURRENT_DATE
        LEFT JOIN descuentos d ON d.id = ppd.descuento_id
        LEFT JOIN motivos m ON m.id = d.motivo_id
        WHERE pp.nro_cuota >= 1
        GROUP BY pp.id, pp.nro_cuota, pp.concepto_pago_id, pp.inscripcion_id, pcp.nombre, pp.monto
    ) plan_actualizado
    LEFT JOIN detalle_pagos_inscripcion dpi ON plan_actualizado.id = dpi.cuota_id AND dpi.estado = 1
    GROUP BY plan_actualizado.id
) kardex ON kardex.inscripcion_id = i.id
WHERE ei.id IN (0,1,2,3,4,5)
  AND c.nombre IN ('Diplomado', 'Especialidad', 'Maestría')
  AND s.id IN (1,2,3,4,5,6,7,8,14,15,16,18,20,22,23,24,25,26,37,50,52,80,125,127,128,129)
  AND (p.iduniversidad IN (2,9,35,52,128,133) OR p.iduniversidad IS NULL)
GROUP BY i.id
HAVING FECHA_PAGO_1RA_CUOTA BETWEEN '2026-01-01' AND '2026-06-30'
ORDER BY FECHA_PAGO_1RA_CUOTA ASC;