#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
# SPDX-License-Identifier: MPL-2.0
"""Tests de handoff.py: unittest, sin red y sin tocar el proyecto real.

Cada caso crea un proyecto temporal y ejecuta el script como proceso aparte
(`python3 handoff.py <cmd>`) con `cwd` en ese proyecto. No hay API ni stub de
`opencode`: el disparo del subagente no vive en el script.
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import date
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "handoff.py"
SLUG_PATTERN = r"\A[a-z0-9][a-z0-9-]{0,39}\Z"


def today():
    return date.today().isoformat()


class HandoffTestCase(unittest.TestCase):
    """Proyecto temporal aislado + helpers de aserción sobre stdout/stderr del script."""

    def setUp(self):
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.tmp = Path(self._tmpdir.name)
        self.project = self.tmp / "proyecto"
        self.handoffs = self.project / ".opencode" / "handoffs"
        self.config = self.tmp / "config"
        self.project.mkdir()
        self.config.mkdir()

    # --- ejecución -------------------------------------------------------

    def run_handoff(self, *args, timeout=None):
        return subprocess.run(
            [sys.executable, str(SCRIPT)] + list(args),
            check=False, cwd=str(self.project), capture_output=True, text=True,
            env=dict(os.environ, XDG_CONFIG_HOME=str(self.config)), timeout=timeout)

    def ok(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def fails(self, result, code=1):
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def value(self, result, key):
        prefix = key + "="
        return next(line[len(prefix):] for line in result.stdout.splitlines() if line.startswith(prefix))

    # --- fixtures --------------------------------------------------------

    def make_handoffs(self):
        self.handoffs.mkdir(parents=True, exist_ok=True)
        return self.handoffs

    def write_work_file(self, name, content):
        self.make_handoffs()
        path = self.handoffs / name
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding="utf-8")
        return path

    def age_file(self, path, days):
        stamp = time.time() - days * 86400
        os.utime(str(path), (stamp, stamp))

    def make_briefs(self, count, age_days=None):
        """Crea `count` hojas (la 0 es la más nueva) y devuelve la lista en ese orden."""
        self.make_handoffs()
        briefs = []
        for index in range(count):
            brief = self.handoffs / f"{today()}-hoja-{index:02d}.md"
            brief.write_text("# hoja\n", encoding="utf-8")
            self.age_file(brief, age_days if age_days is not None else index / 24)
            briefs.append(brief)
        return briefs

    def make_brief(self, slug="demo", text="# Hand-off: demo\n\nPlan.\n"):
        self.make_handoffs()
        path = self.handoffs / f"{today()}-{slug}.md"
        path.write_text(text, encoding="utf-8")
        return path


class PrepTest(HandoffTestCase):
    def test_prep_crea_directorio_y_limpia_estado_viejo(self):
        for name in (".task", ".candidates"):
            self.write_work_file(name, "viejo")

        result = self.ok(self.run_handoff("prep"))

        self.assertIn("OK prep", result.stdout)
        self.assertTrue(self.handoffs.is_dir())
        for name in (".task", ".candidates"):
            self.assertFalse((self.handoffs / name).exists(), name)

    def test_prep_borra_task_symlink_sin_tocar_la_victima(self):
        victim = self.tmp / "victima.txt"
        victim.write_text("original\n", encoding="utf-8")
        self.make_handoffs()
        os.symlink(str(victim), str(self.handoffs / ".task"))

        self.ok(self.run_handoff("prep"))

        self.assertFalse((self.handoffs / ".task").is_symlink())
        self.assertFalse((self.handoffs / ".task").exists())
        self.assertEqual(victim.read_text(encoding="utf-8"), "original\n")

    def test_prep_falla_si_handoffs_es_symlink(self):
        self.project.joinpath(".opencode").mkdir()
        outside = self.tmp / "afuera"
        outside.mkdir()
        os.symlink(str(outside), str(self.handoffs))

        result = self.fails(self.run_handoff("prep"))

        self.assertIn("symlink", result.stderr)
        self.assertEqual(list(outside.iterdir()), [])

    def test_prep_falla_si_opencode_apunta_afuera(self):
        outside = self.tmp / "afuera"
        outside.mkdir()
        os.symlink(str(outside), str(self.project / ".opencode"))

        self.fails(self.run_handoff("prep"))

        self.assertEqual(list(outside.iterdir()), [])

    def test_prep_rechaza_raiz_invalida(self):
        for invalid in ("/", ".", str(self.project) + "/.."):
            with self.subTest(root=invalid):
                self.fails(self.run_handoff("--project", invalid, "prep"))


class SlugTest(HandoffTestCase):
    def test_slug_sanea_acentos_comillas_saltos_y_nul(self):
        task = "Migrar a OAuth ÑANDÚ $(touch PWNED) \"dobles\" 'simples'\nsegunda línea\x00fin"
        self.write_work_file(".task", task.encode("utf-8"))

        result = self.ok(self.run_handoff("slug"))

        slug = self.value(result, "SLUG")
        self.assertRegex(slug, SLUG_PATTERN)
        self.assertEqual(self.value(result, "BRIEF"), str(self.handoffs / f"{today()}-{slug}.md"))
        self.assertFalse((self.project / "PWNED").exists())
        self.assertFalse((self.handoffs / ".task").exists())

    def test_slug_colision_agrega_sufijo(self):
        self.write_work_file(".task", "handoff de prueba")
        brief = Path(self.value(self.ok(self.run_handoff("slug")), "BRIEF"))
        brief.write_text("# primera\n", encoding="utf-8")

        self.write_work_file(".task", "handoff de prueba")
        again = self.ok(self.run_handoff("slug"))

        self.assertEqual(Path(self.value(again, "BRIEF")), self.handoffs / (brief.stem + "-2.md"))

    def test_slug_falla_si_task_es_symlink(self):
        self.make_handoffs()
        target = self.tmp / "afuera.txt"
        target.write_text("texto", encoding="utf-8")
        os.symlink(str(target), str(self.handoffs / ".task"))

        self.assertIn("symlink", self.fails(self.run_handoff("slug")).stderr)

    def test_slug_falla_si_falta_task(self):
        self.make_handoffs()
        self.assertIn(".task", self.fails(self.run_handoff("slug")).stderr)

    def test_slug_no_deja_archivos_de_estado(self):
        self.write_work_file(".task", "una tarea")

        self.ok(self.run_handoff("slug"))

        self.assertEqual(sorted(path.name for path in self.handoffs.iterdir()), [])


class SealTest(HandoffTestCase):
    def seal(self, brief):
        return self.run_handoff("seal", "--brief", str(brief))

    def test_seal_hoja_limpia(self):
        brief = self.make_brief()

        result = self.ok(self.seal(brief))

        self.assertIn("SCAN=limpio", result.stdout)
        self.assertNotIn("HASH", result.stdout)

    def test_seal_detecta_secreto_sin_imprimirlo(self):
        brief = self.make_brief(text="# Hand-off\n\n    password: hunter2\n")

        result = self.fails(self.seal(brief))

        self.assertIn("LINEA 3", result.stdout)
        self.assertNotIn("hunter2", result.stdout + result.stderr)

    def test_seal_no_matchea_prosa(self):
        brief = self.make_brief(text="# Hand-off\n\nEl flujo de password reset queda fuera de alcance.\n"
                                     "No guardes secretos en el repo; el tokenizer usa BPE.\n")
        self.assertIn("SCAN=limpio", self.ok(self.seal(brief)).stdout)

    def test_seal_detecta_tokens_de_nuevo_formato(self):
        brief = self.make_brief(text="# Hand-off\n\nOPENAI=sk-proj-AbCdEf1234567890xy\n"
                                     "GITLAB=glpat-AbCdEf1234567890\n")

        result = self.fails(self.seal(brief))

        self.assertIn("LINEA 3", result.stdout)
        self.assertIn("LINEA 4", result.stdout)
        self.assertNotIn("AbCdEf", result.stdout + result.stderr)


    def test_seal_sin_brief_falla(self):
        self.make_handoffs()
        self.fails(self.run_handoff("seal"), code=2)

    def test_seal_fuera_de_handoffs_falla(self):
        outside = self.tmp / "afuera.md"
        outside.write_text("# Hand-off\n\nPlan.\n", encoding="utf-8")

        result = self.fails(self.seal(outside))

        self.assertIn("handoffs", result.stderr)

    def test_seal_rechaza_hoja_que_no_es_md(self):
        self.make_handoffs()
        other = self.handoffs / "notas.txt"
        other.write_text("# Hand-off\n\nPlan.\n", encoding="utf-8")

        self.assertIn(".md", self.fails(self.seal(other)).stderr)

    def test_seal_rechaza_symlink(self):
        victim = self.make_brief("victima")
        link = self.handoffs / f"{today()}-link.md"
        os.symlink(str(victim), str(link))

        self.assertIn("symlink", self.fails(self.seal(link)).stderr)

    def test_seal_rechaza_hoja_vacia(self):
        brief = self.make_brief(text="   \n")
        self.assertIn("vacía", self.fails(self.seal(brief)).stderr)

    def test_seal_falla_si_handoffs_es_symlink(self):
        outside = self.tmp / "afuera"
        outside.mkdir()
        (outside / "hoja.md").write_text("# Hand-off\n\nPlan.\n", encoding="utf-8")
        self.project.joinpath(".opencode").mkdir()
        os.symlink(str(outside), str(self.handoffs))

        self.fails(self.run_handoff("seal", "--brief", str(outside / "hoja.md")))


class ScanTest(HandoffTestCase):
    def test_scan_detecta_los_dos_excedentes(self):
        briefs = self.make_briefs(12)

        result = self.ok(self.run_handoff("scan"))

        self.assertIn("TOTAL=2", result.stdout)
        candidates = json.loads((self.handoffs / ".candidates").read_text(encoding="utf-8"))
        self.assertEqual(sorted(candidates), sorted(str(path) for path in briefs[-2:]))
        self.assertEqual((self.handoffs / ".candidates").stat().st_mode & 0o777, 0o600)

    def test_scan_incluye_hoja_de_20_dias(self):
        briefs = self.make_briefs(2)
        vieja = self.handoffs / f"{today()}-vieja.md"
        vieja.write_text("# hoja\n", encoding="utf-8")
        self.age_file(vieja, 20)

        result = self.ok(self.run_handoff("scan"))

        self.assertIn("TOTAL=1", result.stdout)
        stored = json.loads((self.handoffs / ".candidates").read_text(encoding="utf-8"))
        self.assertEqual(stored, [str(vieja)])
        self.assertTrue(all(path.exists() for path in briefs))

    def test_scan_no_ejecuta_nombres_hostiles(self):
        self.make_handoffs()
        hostile = self.handoffs / f"{today()}-pwned $(touch PWNED) `touch PWNED2`.md"
        hostile.write_text("# hoja\n", encoding="utf-8")
        self.age_file(hostile, 5)
        self.make_briefs(11)

        result = self.ok(self.run_handoff("scan"))

        self.assertIn("TOTAL=2", result.stdout)
        self.assertIn("$(touch PWNED)", result.stdout)
        for pwned in ("PWNED", "PWNED2"):
            self.assertFalse((self.project / pwned).exists(), pwned)
            self.assertFalse((self.tmp / pwned).exists(), pwned)

    def test_scan_ignora_subdirectorios(self):
        self.make_handoffs()
        nested = self.handoffs / "sub"
        nested.mkdir()
        inner = nested / f"{today()}-inner.md"
        inner.write_text("# hoja\n", encoding="utf-8")
        self.age_file(inner, 40)

        result = self.ok(self.run_handoff("scan"))

        self.assertIn("nada para borrar", result.stdout)
        self.assertFalse((self.handoffs / ".candidates").exists())

    def test_scan_y_delete_borran_nombre_con_salto_de_linea(self):
        self.make_handoffs()
        hostile = self.handoffs / f"{today()}-evil\\nANSI.md"
        hostile.write_text("# hoja\n", encoding="utf-8")
        self.age_file(hostile, 30)

        result = self.ok(self.run_handoff("scan"))

        self.assertIn("TOTAL=1", result.stdout)
        stored = json.loads((self.handoffs / ".candidates").read_text(encoding="utf-8"))
        self.assertEqual(stored, [str(hostile)])

        deleted = self.ok(self.run_handoff("delete"))

        self.assertIn("BORRADOS=1 FALLOS=0", deleted.stdout)
        self.assertFalse(hostile.exists())

    def test_scan_rechaza_candidates_fifo_sin_colgarse(self):
        brief = self.make_brief("vieja")
        self.age_file(brief, 30)
        os.mkfifo(str(self.handoffs / ".candidates"))

        result = self.fails(self.run_handoff("scan", timeout=15))

        self.assertIn("FIFO", result.stderr)


class DeleteTest(HandoffTestCase):
    def test_delete_respeta_guards_y_no_corta_en_el_primer_fallo(self):
        first = self.make_brief("uno")
        second = self.make_brief("dos")
        intacto = self.make_brief("intacto")
        nested = self.handoffs / "sub"
        nested.mkdir()
        inner = nested / "inner.md"
        inner.write_text("# inner\n", encoding="utf-8")
        outside = self.tmp / "victima.md"
        outside.write_text("# victima\n", encoding="utf-8")
        link = self.handoffs / f"{today()}-link.md"
        os.symlink(str(outside), str(link))
        (self.handoffs / ".candidates").write_text(
            json.dumps([str(link), str(second), str(inner), str(first)]), encoding="utf-8")

        result = self.fails(self.run_handoff("delete"))

        self.assertIn("BORRADOS=2 FALLOS=2", result.stdout)
        self.assertFalse(first.exists())
        self.assertFalse(second.exists())
        self.assertTrue(link.is_symlink())
        self.assertTrue(outside.exists())
        self.assertTrue(inner.exists())
        self.assertTrue(intacto.exists())
        self.assertFalse((self.handoffs / ".candidates").exists())

    def test_delete_no_borra_archivos_de_trabajo(self):
        task = self.write_work_file(".task", "tarea")
        (self.handoffs / ".candidates").write_text(json.dumps([str(task)]), encoding="utf-8")

        result = self.fails(self.run_handoff("delete"))

        self.assertIn("FALLOS=1", result.stdout)
        self.assertTrue(task.exists())

    def test_delete_sin_candidates_falla(self):
        self.make_handoffs()
        self.assertIn("scan", self.fails(self.run_handoff("delete")).stderr)

    def test_delete_rechaza_candidates_que_no_es_lista(self):
        self.write_work_file(".candidates", json.dumps({"ruta": "/tmp/x.md"}))

        self.assertIn("lista", self.fails(self.run_handoff("delete")).stderr)

    def test_discard_borra_candidates(self):
        self.write_work_file(".candidates", json.dumps(["/tmp/x.md"]))
        result = self.ok(self.run_handoff("discard"))
        self.assertIn("descartado", result.stdout)
        self.assertFalse((self.handoffs / ".candidates").exists())

    def test_discard_falla_si_handoffs_es_symlink(self):
        outside = self.tmp / "afuera"
        outside.mkdir()
        (outside / ".candidates").write_text("[]", encoding="utf-8")
        self.project.joinpath(".opencode").mkdir()
        os.symlink(str(outside), str(self.handoffs))

        self.fails(self.run_handoff("discard"))

        self.assertTrue((outside / ".candidates").exists())


if __name__ == "__main__":
    unittest.main()
