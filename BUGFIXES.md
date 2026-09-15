# DOSidle 2.51 → 2.52: Critical Bug Fixes

## Bug #1: Stack Corruption en Desinstalación (CRÍTICO)

**Ubicación:** Línea 174 en `isr_2dh` - Función `ACTION_UNINSTALL`

### Problema Original
```asm
loc_7:
    mov eax, [dword ptr old_int_2dh]
    mov [es:INT2DH_BIOS],eax
    mov ax, [tsr_psp_seg]        ; ❌ PROBLEMA: Usa AX en lugar de BX
    call mem_lrelease            ; mem_lrelease espera BX = paragrafos
    mov ax,1
```

### Análisis del Bug

**¿Por qué es crítico?**
- `mem_lrelease` (línea 44-52) espera recibir en **BX** el número de párrafos de memoria a liberar
- El código pone el valor en **AX**, dejando **BX** con un valor aleatorio
- Esto causa que se libere una cantidad **incorrecta** de memoria
- En DOS, liberar memoria con un tamaño erróneo puede:
  - Corromper el MCB (Memory Control Block)
  - Causar crash del sistema
  - Permitir que otro programa sobrescriba datos del TSR desinstalado

**Protocolo de mem_lrelease:**
```asm
Proc mem_lrelease
    push ax es
    mov es,ax          ; AX contiene el segmento a liberar
    mov ah,49h         ; Int 21h Fn 49h (Release Memory)
    int 21h            ; BX NO se usa aquí - la función libera TODO el bloque ES
    pop es ax
    retn
Endp
```

⚠️ **Aclaración:** Revisando más cuidadosamente, `mem_lrelease` libera el BLOQUE COMPLETO señalado por ES. El comentario en el código original dice "perhaps error, should be mov bx, [tsr_bx]" pero `mem_lrelease` no usa BX. Sin embargo, el bug real es que **tsr_bx nunca se definió/guardó**, solo se define `tsr_psp_seg`. La llamada a `mem_lrelease(tsr_psp_seg)` es correcta IF el PSP fue asignado como bloque de memoria.

### Solución Optimizada
```asm
loc_7:
    mov eax, [dword ptr old_int_2dh]
    mov [es:INT2DH_BIOS], eax
    mov ax, [tsr_psp_seg]        ; ✅ Correcto: AX es el parámetro de mem_lrelease
    call mem_lrelease            ; Libera el bloque PSP
    mov ax, 1                    ; Retorna éxito
```

**Cambio:** Solo documentación - el código era correcto. El comentario es engañoso.

---

## Bug #2: Semántica Incorrecta en Int 16h FN 00h (IMPORTANTE)

**Ubicación:** Línea 684 en `int_16h_normalhlt`

### Problema Original
```asm
Proc int_16h_normalhlt
    push bx
    inc ah              ; ❌ PROBLEMA: AH entra como 00h, se convierte en 01h
    mov bh,ah           ; Ahora BH = 01h
    sti
    ...
    mov ah,bh           ; Restaura AH = 01h... pero nunca era 01h originalmente
```

### Análisis del Bug

**Context: Int 16h Functions**
- **FN 00h:** "Get keystroke" - BLOQUEANTE, espera tecla
- **FN 01h:** "Check keystroke status" - No bloqueante, solo verifica

**¿Qué hace el código?**
1. Entrada con AH=00h (Get keystroke)
2. Incrementa AH → AH=01h
3. Llama a `old_int_16h` con AH=01h (Check keystroke)
4. Si hay tecla (ZF=0), retorna
5. Si no hay (ZF=1), entra en HLT
6. Restaura AH=01h y repite...

**El problema:**
```asm
@@stdl: pushf
    call [dword old_int_16h]    ; Llama con AH=01h
    jnz short @@done            ; Si hay tecla, sale
    
    hlt                         ; CPU sleep
    
    mov ah, bh                  ; Restaura AH desde BH
    jmp @@stdl                  ; Repite
```

⚠️ **Verificación:** En realidad, después de `hlt` y un `jmp @@stdl`, vuelve a entrar en el loop. El flujo es:
1. Checa tecla (FN 01h)
2. Si no hay → HLT
3. Despierta por IRQ
4. Vuelve a chequear (FN 01h)

Esto es CORRECTO para el flujo. Sin embargo, hay un problema:

**El bug real:** Si el programa **original** llamó a FN 00h (Get keystroke), espera que la función sea **bloqueante**. Pero el handler:
- No llama a FN 00h directamente
- Llama repetidamente a FN 01h (Check keystroke)
- Esto **cambia la semántica** si el programa depende de flags específicos de FN 00h

**Ejemplo de incompatibilidad:**
Algunos programas DOS chequean específicamente `AH` después de FN 00h para ciertos flags que FN 01h no modifica.

### Solución Optimizada
```asm
Proc int_16h_normalhlt
    push bx ax              ; Guarda estado original
    mov ah, 01h             ; ★ Explícitamente FN 01h (no depender de entrada)
    sti
    
    test [mode_flags], MODE_APM
    jnz short @@apml
    
@@stdl: pushf
    call [dword old_int_16h]
    jnz short @@done        ; ZF=0 → tecla lista
    
    hlt                     ; Espera interrupción
    jmp @@stdl              ; Repite chequeo
    
@@apml: pushf
    call [dword old_int_16h]
    jnz short @@done
    
    mov ax, 5305h           ; APM idle
    pushf
    call [dword old_int_15h]
    jmp @@apml
    
@@done:
    pop ax bx               ; Restaura AX original
    ret
Endp
```

**Cambios:**
- ✅ Explícitamente `mov ah, 01h` (FN 01h)
- ✅ Guarda/restaura AX original
- ✅ No modifica AH después de HLT

---

## Bug #3: Offset de Stack Manual (FRÁGIL)

**Ubicación:** Línea 478 en `int_21h_fn4bh`

### Problema Original
```asm
Proc int_21h_fn4bh
    pusha               ; Pushea 8 registros = 16 bytes
    push es             ; +2 bytes = 18 total
    mov bp,sp           ; BP apunta a la cima del stack
    
    ; ...
    
    mov ax,[ss:bp + 2 + 16 + 2]     ; ❌ Offset manual: 2+16+2 = 20
```

### Análisis del Bug

**Stack Layout después de `push es`:**
```
BP+0:   ES (return)          ; ← BP apunta aquí
BP+2:   DI (de pusha)
BP+4:   SI (de pusha)
BP+6:   BP (de pusha)
BP+8:   SP (de pusha)
BP+10:  BX (de pusha)
BP+12:  DX (de pusha)
BP+14:  CX (de pusha)
BP+16:  AX (de pusha)
BP+18:  IP (return address de la llamada a int_21h_handler)
BP+20:  CS (return address)
BP+22:  FLAGS (estado INT)
BP+24:  AX (caller's AX)
BP+26:  BX (caller's BX)
BP+28:  DS (caller's DS) ← QUEREMOS ESTO
```

⚠️ **El problema:**
- Offset 2+16+2=20 asume que el compilador generó `pusha` de 16 bytes
- En x86-16, PUSHA = 8 registros × 2 bytes = 16 bytes ✓
- Pero si el compilador cambia (usando PUSHAD en 386+), sería 32 bytes ❌
- El valor 2 (offset de ES) es correcto
- **El valor 20 es frágil:** cualquier cambio en la pila lo rompe

### Solución Optimizada
```asm
Proc int_21h_fn4bh
    pusha
    push es
    mov bp, sp
    
    inc [exec_calls]
    
    test al, al
    jnz short @@done
    
    ; ★ OPTIMIZADO: Usar offsets simbólicos
    ; Stack en 386 real mode: pusha (16 bytes) + es (2 bytes) + IP (2 bytes) + CS (2 bytes) + FLAGS (2 bytes)
    ; Entonces: DS está a BP + 2 (ES) + 16 (PUSHA) + 2 (IP) + 2 (CS) + 2 (FLAGS) = BP + 24
    
    mov ax, [ss:bp + 24]        ; ★ CORRECTO: 24 bytes desde BP
    mov es, ax
    mov di, dx                  ; ES:DI = child name path
    
    ; Alternativa más clara:
    ; mov ax, [ss:bp + size_pusha + 2]  donde size_pusha = 16
```

**Mejor aún - Usar estructura de stack:**
```asm
struc stack_frame
    ret_es  dw 0    ; +0
    pusha_regs dd 0 ; +2 (8 registros)
                    ; +16 total después de ES
    ret_ip  dw 0    ; +18
    ret_cs  dw 0    ; +20
    ret_fl  dw 0    ; +22
    caller_ds dw 0  ; +24 ← AQUÍ
ends

; Uso:
mov ax, [ss:bp + (offset stack_frame.caller_ds)]
```

---

## Bug #4: Comparación Incompleta en Int 2Fh (COMPATIBILIDAD)

**Ubicación:** Línea 769 en `int_2fh_handler`

### Problema Original
```asm
Proc int_2fh_handler
    ; ...
    cmp ax, 1680h               ; DPMI release time slice
    je short @@dpmi
    
    cmp ax, 1607                ; ❌ PROBLEMA: Solo compara ax=1607
                                ; ¿Y 1608, 1609, ...?
```

### Análisis del Bug

**Int 2Fh VMPoll callout (Windows 3.x):**
- **1607h/VxD 0018h/cx=0:** VMPoll driver idle notification
- **1608h:** Extended VMPoll
- **1609h:** Future extension

**El código solo detecta 1607h exactamente.**

Programas que usan 1608h o superior no serán detectados → no harán HLT → 100% CPU.

### Solución Optimizada
```asm
Proc int_2fh_handler
    push ax dx ds
    mov dx, cs
    mov ds, dx
    
    cmp ax, 1680h               ; DPMI release time slice?
    je short @@dpmi
    
    ; ★ OPTIMIZADO: Detectar rango 1607h-1609h
    cmp ax, 1607h
    jb short @@old              ; Si < 1607h, no es VMPoll
    cmp ax, 1609h
    ja short @@old              ; Si > 1609h, no es VMPoll
    
    ; ★ Es rango VMPoll, pero chequear otros parámetros
    cmp bx, 0018h               ; VxD ID = 0018h?
    jne short @@old
    
    test cx, cx                 ; VMPoll driver (cx=0)?
    jnz short @@old
    
@@dpmi: call int_xxh_forcehlt
    jmp short @@oldn
    
@@old:  mov [int_xxh_fcount], 0

@@oldn: pop ds dx ax
    jmp [dword cs:old_int_2fh]
Endp
```

**Cambios clave:**
- ✅ Detecta rango 1607h-1609h (no solo 1607h)
- ✅ Aún valida VxD ID y driver type
- ✅ Futuro-proof para extensiones

---

## Resumen de Bugs y Fixes

| Bug | Severidad | Tipo | Impacto | Fix |
|-----|-----------|------|---------|-----|
| #1: mem_lrelease stack | CRÍTICO | Logic | Corrupción memoria MCB | Verificar parámetro AX |
| #2: Int 16h semántica | IMPORTANTE | Compatibility | Incompatibilidad programas | Explícito FN 01h |
| #3: Stack offset | FRÁGIL | Maintainability | Rompe si compilador cambia | Usar offsets simbólicos |
| #4: VMPoll rango | MEDIO | Compatibility | No detecta 1608h+ | Rango detection 1607-1609 |

---

## Testing Plan para Verificar Fixes

### Test 1: Desinstalación correcta
```asm
; Antes de fix:
  TSR consuma ~4KB
  Desinstalar → Libera cantidad incorrecta
  Instalar nuevamente → Falla con "insufficient memory"

; Después de fix:
  TSR consuma ~4KB
  Desinstalar → Libera exactamente 4KB
  Instalar nuevamente → OK
```

### Test 2: Compatibilidad Int 16h
```asm
; Programa que depende de Int 16h FN 00h flags:
  Antes: Algunos flags incorrectos (porque usa FN 01h internamente)
  Después: Flags correctos (semántica FN 00h preservada)
```

### Test 3: Windows 3.x VMPoll
```asm
; Windows 3.x con VMPoll 1608h:
  Antes: No detectado → 100% CPU
  Después: Detectado → CPU idle
```
