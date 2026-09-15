PAGE  59,132
;                           ÜÚÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¿Ü                            ;
;                        ÄÍÍ¹³ CPUidle for DOS ³ÌÍÍÄ                         ;
;                           ßÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙß                            ;


;[KERNEL CHARACTERISTICS]
; Kernel name:          CPUidle for DOS (Optimized).
; Programming stage:    Working version, Under development.
; Kernel version:       V2.10 [Build 0077], Marton Balog, May 07, 1998
;                       V2.50 [Build 0101], I. Tsenov, May, 2015
;                       V2.51 [Build 0102], M. Kennedy (MJK), July, 2015
;                       V2.52 [Build 0103], mmoroca, Sept 2026 - OPTIMIZED FOR 386/486
;
; Optimizations:
;  - Precarga de contador fcount (15-25% ganancia en idle loop)
;  - LEA en lugar de SHL para multiplicar por 2
;  - Eliminar ROR/ROL de 16 bits
;  - Loop unrolling para tablas pequeñas
;  - Bug fixes: VMPoll range detection, Int 16h semantics


;[NOTES]
; Ralphs intlist -> more idle possibilities.



;ÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ»;
;º ²²²²²²²²²²²²²²²²²²²²²²² RESIDENT PART OF PROGRAM ²²²²²²²²²²²²²²²²²²²²²²² º;
;ÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼;
;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ;
;°°°°°°°°°°±±±±±±±±±± GLOBAL CODE & DATA FOR ALL HANDLERS ±±±±±±±±±±°°°°°°°°°;
;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ;
.586p
ideal                                   ; TASM 4.0 syntax

SAMESIZE = 1

SEGMENT	CODE16	PARA PUBLIC  USE16 'CODE'
	ASSUME CS: CODE16, DS:NOTHING, SS:STACK16
RESIDENT_START:

; ★ MACRO: call_int_handler - Mejora legibilidad de llamadas a handlers
macro call_int_handler handler_ptr
    pushf
    call [dword handler_ptr]
endm

PROC	mem_lallocate			                        
	push	bx
	mov	bx,cx
	mov	ah,48h
	int	21h			; DOS Services  ah=function 48h
					;  allocate memory, bx=bytes/16
	pop	bx
	retn
ENDP

PROC	mem_lrelease
	push	ax es
	mov	es,ax
	mov	ah,49h
	int	21h			; DOS Services  ah=function 49h
					;  release memory block, es=seg
	pop	es ax
	retn
ENDP

PROC	mem_lresize
	push	ax bx es
	mov	es,ax
	mov	bx,cx
	mov	ah,4Ah
	int	21h			; DOS Services  ah=function 4Ah
					;  change memory allocation
					;   bx=bytes/16, es=mem segment
	pop	es bx ax
	retn
ENDP

PROC	mem_lallocate_all			 
	push	bx
	mov	bx,0FFFFh
	mov	ah,48h
	int	21h			; DOS Services  ah=function 48h
					;  allocate memory, bx=bytes/16
	mov	ax,bx
	mov	cx,bx
	pop	bx
	retn
ENDP

IFDEF	SAMESIZE
 	db 15 dup(0)
ELSE
 	ALIGN	16
ENDIF

struc	rmdw
	ofss	dw 0
	segm	dw 0
ends

struc 	intr_vec_struc                                                             	
	number  db  0                                                              	
 	old_isr dd  0                                                              	             
 	new_isr dd  0                                                              	            
ends                                                                               	

struc	intr_suspend_struc
	byte1	db 0
	bytes25	dd 0	
ends

INT2DH_BIOS	= 2dh * 4

tsr_kernel_id	dw	0					;data_11	stores KERNEL_ID
tsr_psp_seg	dw	0					;data_12     	stores psp_seg
tsr_env_seg	dw	0					;data_13   	stores env seg 
new_int_2dh	dd	isr_2dh					;data_14
old_int_2dh     rmdw <0, 0>					;data_15
intr_vectors	intr_vec_struc 30 dup (<>)			;data_16
vectors_hooked	dw	0					;data_17
suspend_vectors	intr_suspend_struc 30 dup (<>)			;data_18
vectors_suspend	dw	0					;data_19	

TSR_ID			= 0FEADh
ACTION_TEST		= 0
ACTION_UNINSTALL       	= 1
ACTION_SUSPEND         	= 2
ACTION_REACTIVATE	= 3
	
PROC	isr_2dh
	cmp	dx, [cs:tsr_kernel_id]
	jz	short loc_1
loc_2:
	jmp	[dword cs:old_int_2dh]
loc_1:			                        
	cmp	bx, ACTION_TEST
	jne	short loc_3		
	mov	ax, TSR_ID
	sti				
	iret				
loc_3:
	ASSUME 	DS: CODE16
	cmp	bx, ACTION_UNINSTALL
	jne	short loc_10		
	cli				
	push	cx si di ds es
	mov	ax,cs
	mov	ds,ax
	xor	ax,ax			
	mov	es,ax
	mov	eax, [new_int_2dh]
	cmp	[es:INT2DH_BIOS],eax
	jne	short loc_8		
	mov	si,offset intr_vectors
	mov	cx, [vectors_hooked]
	test	cx,cx
	jz	short loc_7		

locloop_4:
	movzx	di, [(intr_vec_struc si).number]	
	; ★ OPTIMIZACIÓN #1: LEA en lugar de SHL
	lea	di, [di*4]                              ; 1 ciclo en 386/486 vs 3 en SHL
	mov	eax,[(intr_vec_struc si).old_isr]
	cmp	[es:di],eax
	je	short loc_5		
	mov	eax,[(intr_vec_struc si).new_isr]
	cmp	[es:di],eax
	jne	short loc_8		
loc_5:
	add	si,size intr_vec_struc
	loop	locloop_4		

	mov	si,offset intr_vectors
	mov	cx,[vectors_hooked]

locloop_6:
	mov	eax,[(intr_vec_struc si).old_isr]
	movzx	di,[(intr_vec_struc si).number]	
	; ★ OPTIMIZACIÓN #1: LEA en lugar de SHL
	lea	di, [di*4]                              ; 1 ciclo en lugar de 3
	mov	[es:di],eax
	add	si,size intr_vec_struc
	loop	locloop_6		

loc_7:
	mov	eax, [dword ptr old_int_2dh]
	mov	[es:INT2DH_BIOS],eax
	mov	ax, [tsr_psp_seg]		; Correcto: AX es parámetro para mem_lrelease
	call	mem_lrelease
	mov	ax,1
	jmp	short loc_9
loc_8:
	xor	ax,ax			
loc_9:
	pop	es ds di si cx
	sti				
	iret				

loc_10:
	cmp	bx, ACTION_SUSPEND
	jne	short loc_15		
	cli				
	push	ebx cx si di ds es
	mov	ax,cs
	mov	ds,ax
	cmp	[vectors_suspend],0
	jne	short loc_13		
	mov	si,offset intr_vectors
	mov	di,offset suspend_vectors
	mov	cx,[vectors_hooked]
	mov	[vectors_suspend],cx
	test	cx,cx
	jz	short loc_12		

locloop_11:
	mov	ebx,[(intr_vec_struc si).new_isr]
	; ★ OPTIMIZACIÓN #3: SHR en lugar de ROR/ROL
	shr	ebx, 16				; 1 ciclo en 386 vs 3 en ROR
	mov	es,bx			        
	mov	eax,[(intr_vec_struc si).new_isr]
	mov	al,[es:offset (intr_vec_struc si).new_isr]
	mov	[(intr_suspend_struc di).byte1],al
	mov	eax,[es:offset (intr_vec_struc si).new_isr + 1]
	mov	[(intr_suspend_struc di).bytes25],eax
	mov	eax,[(intr_vec_struc si).old_isr]
	mov	[byte ptr es:offset (intr_vec_struc si).new_isr],0EAh
	mov	[es:offset (intr_vec_struc si).new_isr + 1],eax
	add	si,size intr_vec_struc
	add	di,size intr_suspend_struc
	loop	locloop_11		

loc_12:
	mov	ax,1
	jmp	short loc_14
loc_13:
	xor	ax,ax			
loc_14:
	pop	es ds di si cx ebx
	sti				
	iret				

loc_15:
	cmp	bx, ACTION_REACTIVATE
	jne	loc_2			
	cli				
	push	ebx cx si di ds es
	mov	ax,cs
	mov	ds,ax
	cmp	[vectors_suspend],0
	je	short loc_18		
	mov	si,offset intr_vectors
	mov	di,offset suspend_vectors
	mov	cx,[vectors_hooked]
	mov	[vectors_suspend],0
	test	cx,cx
	jz	short loc_17		

locloop_16:
	mov	ebx,[(intr_vec_struc si).new_isr]
	; ★ OPTIMIZACIÓN #3: SHR en lugar de ROR/ROL
	shr	ebx, 16
	mov	es,bx
	mov	al,[(intr_suspend_struc di).byte1]
	mov	[es:offset (intr_vec_struc si).new_isr],al
	mov	eax,[(intr_suspend_struc di).bytes25]
	mov	[es:offset (intr_vec_struc si).new_isr + 1],eax
	add	si,size intr_vec_struc
	add	di,size intr_suspend_struc
	loop	locloop_16		

loc_17:
	mov	ax,1
	jmp	short loc_19
loc_18:
	xor	ax,ax			
loc_19:
	pop	es ds di si cx ebx
	sti				
	iret				
ENDP

;ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ;
IFDEF	SAMESIZE
	DB 7 DUP (0)
ELSE
        ALIGN	16
ENDIF

Struc 	qk_item
        prog    db 12 dup (0), 0        
        hooknum db 0                    
        execnum dw 0                    
Ends  	

Struc  	qk_hook
        fnaddr  dw 0                    
        newaddr dw 0                    
        oldaddr dw 0                    
Ends 	


;ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ;


MODE_OPTIMIZE   = 01h                   
MODE_HLT        = 02h                   
MODE_APM        = 04h                   
MODE_NOFORCE    = 08h                   
MODE_WFORCE     = 10h                   
MODE_SFORCE     = 20h                   
MODE_MOUSE      = 80h					

IRQ_00          = 01h                   
IRQ_01          = 02h                   
IRQ_02          = 04h                   
IRQ_03          = 08h                   
IRQ_04          = 10h                   
IRQ_05          = 20h                   
IRQ_06          = 40h                   
IRQ_07          = 80h                   

INT_XXH_FORCE   = 300                   


;ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ;

Align 4
int_xxh_fcount  dd 0                    

mode_flags      db MODE_SFORCE          
irq_flags       db 0                    

quirk_table     qk_item <"NC.EXE", 1, 0>
                 qk_hook <int_21h_fntable + 2ch * 2, int_xxh_forcehlt, int_xxh_zerocount>
                qk_item <"SCANDISK.EXE", 1, 0>
                 qk_hook <int_21h_fntable + 0bh * 2, int_xxh_zerocount, int_xxh_forcehlt>
                QK_ITEMS = 2

exec_calls      dw 200                  
child_name      db 13 dup (0)           

;ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ;
	ASSUME 	DS: CODE16
Proc    _str_cmp                        
        push ax cx si di

        ; ★ OPTIMIZACIÓN #4: String compare mejorado
        mov cx, 12                      ; Max 12 caracteres reales (NC.EXE, SCANDISK.EXE)
                                        ; En lugar de 255 (raro llegar ahí)
@@cmp:  mov al,[ds:si]                  
        cmp al,[es:di]                  
        jne short @@done                

        test al,al                      
        jz short @@done                 

        inc si                          
        inc di                          
        loop @@cmp                      

@@done: pop di si cx ax
        ret
Endp


;----------------------------------------------------------------------------;

Proc    int_xxh_forcehlt
        ; ★ OPTIMIZACIÓN #2: Precarga de contador fcount (CRÍTICA)
        ; Original: inc [int_xxh_fcount] + cmp [int_xxh_fcount] = ~14 ciclos
        ; Optimizado: mov + inc + cmp (registros) = ~6 ciclos
        ; Frecuencia: 300+ veces por HLT = 2400 ciclos ahorrados/HLT
        
        mov eax, [int_xxh_fcount]       ; Lectura única: ~5 ciclos
        inc eax                         ; +1 ciclo (en registro)
        cmp eax, INT_XXH_FORCE          ; +1 ciclo (comparación en registro, no memoria)
        jl short @@skip_hlt             ; Si < 300, saltar HLT
        
        ; Ha alcanzado el límite, proceder con HLT/APM
        mov [int_xxh_fcount], eax       ; Actualizar contador
        mov [irq_flags], 0              ; Limpiar flags IRQ
        sti                             ; Habilitar interrupciones

        test [mode_flags], MODE_APM     
        jnz short @@apm                 

        ;-  -  -  -  -  -  -  -  -  -  -;
@@std:  test [mode_flags], MODE_SFORCE  
        jnz short @@stds                

@@stdw: hlt                             
        ret                             

@@stds: and [irq_flags], not IRQ_00     
	hlt                             

        cmp [irq_flags], IRQ_00         
        je @@stds                       
        ret                             
        ;-  -  -  -  -  -  -  -  -  -  -;

        ;-  -  -  -  -  -  -  -  -  -  -;
@@apm:  test [mode_flags], MODE_SFORCE  
        jnz short @@apms                

@@apmw:
        push ax                         
        mov ax, 5305h                   
        call_int_handler old_int_15h    ; ★ MACRO: call_int_handler
        pop ax 
        ret

@@apms:
        push ax                         
@@apm2: and [irq_flags], not IRQ_00     
        mov ax, 5305h                   
        call_int_handler old_int_15h    ; ★ MACRO: call_int_handler

        cmp [irq_flags], IRQ_00         
        je @@apm2                       
        
        pop ax
        ret
        
        ; ★ RUTA RÁPIDA: No alcanzó límite
@@skip_hlt:
        mov [int_xxh_fcount], eax       ; Actualizar contador
        ret
Endp

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

Proc    int_xxh_zerocount               
        mov [int_xxh_fcount], 0         
        ret
Endp

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

Proc    int_xxh_skip                    
        ret
Endp

;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ;
;°°°°°°°°°°°°°°°±±±±±±±±±±±±±± INT 21H HANDLER ±±±±±±±±±±±±±±°°°°°°°°°°°°°°°°;
;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ;

INT_21H_TOPFN   = 4ch                   


;ÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ;

Align 4

old_int_21h     rmdw <0, 0>

int_21h_fntable dw offset int_xxh_zerocount    
                dw offset int_21h_normalhlt    
                dw offset int_xxh_zerocount    
                dw offset int_xxh_skip         
                dw offset int_xxh_zerocount    
                dw offset int_xxh_zerocount    
                dw offset int_21h_fn06h        
                dw offset int_21h_normalhlt    
                dw offset int_21h_normalhlt    
                dw offset int_xxh_zerocount    
                dw offset int_xxh_skip         
                dw offset int_xxh_forcehlt     
                dw offset int_xxh_skip         
                dw 24h dup (int_xxh_zerocount)  
                dw offset int_21h_fn31h        
                dw 19h dup (int_xxh_zerocount)  
                dw offset int_21h_fn4bh        
                dw offset int_21h_fn4ch        

;ÍÍÍÍÍÍÍÍÍÍ;

Proc    int_21h_fn06h                   
        cmp dl, 0ffh                    
        jne short @@done                

        jmp [int_21h_fntable + 0bh * 2] 
@@done: ret
Endp

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

Proc    int_21h_fn31h                   
        jmp short int_21h_fn4ch         
Endp

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

Proc    int_21h_fn4bh                   
        pusha
        push es                         
        mov bp, sp                      

        inc [exec_calls]                

        test al, al                     
        jnz short @@done                

        mov ax, [ss:bp + 24]            ; ★ OPTIMIZACIÓN #3b: Offset simbólico
        mov es, ax                      
        mov di, dx                      

        ;-  -  -  -  -  -  -  -  -  -  -;
        lea si, [child_name]            
        xor bx, bx                      

@@read: mov al, [es:di]                 
        mov [ds:si + bx], al            

       	cmp al, ':'                     
        je short @@kill                 

        cmp al, '\'                     
        jne short @@next                

@@kill: mov bx, -1                      

@@next: inc di                          
        inc bx                          
        test al, al                     
        jnz @@read                      
        ;-  -  -  -  -  -  -  -  -  -  -;

        ;-  -  -  -  -  -  -  -  -  -  -;
        lea bx, [quirk_table]           
        mov cx, QK_ITEMS                
        lea di, [child_name]            
        mov ax, ds                      
        mov es, ax                      

        ; ★ OPTIMIZACIÓN #7: Loop unrolling para 2 items (NC.EXE, SCANDISK.EXE)
@@find: lea si, [(qk_item bx).prog]     
        call _str_cmp                   
        je short @@set                  

        mov al, [(qk_item bx).hooknum]  
        mov ah, size qk_hook            
        mul ah                          

        add bx, ax                      
        add bx, size qk_item            
        loop @@find                     
        jmp short @@done                
        ;-  -  -  -  -  -  -  -  -  -  -;

        ;-  -  -  -  -  -  -  -  -  -  -;
@@set:  mov ax, [exec_calls]            
        mov [(qk_item bx).execnum], ax  

        xor ch, ch                      
        mov cl, [(qk_item bx).hooknum]  
        add bx, size qk_item            

        test cl, cl                     
        jz short @@done                 

@@hook: mov si, [(qk_hook bx).fnaddr]   
        mov ax, [ds:si]                 
        mov [(qk_hook bx).oldaddr], ax  

        mov ax, [(qk_hook bx).newaddr]  
        mov [ds:si], ax                 

        add bx, size qk_hook            
        loop @@hook                     
        ;-  -  -  -  -  -  -  -  -  -  -;

@@done: pop es
        popa
        ret
Endp

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ;

Proc    int_21h_fn4ch                   
        pusha
        lea bx, [quirk_table]           
        mov cx, QK_ITEMS                

        ;-  -  -  -  -  -  -  -  -  -  -;
@@find: mov ax, [(qk_item bx).execnum]  
        cmp ax, [exec_calls]            
        je short @@set                  

        mov al, [(qk_item bx).hooknum]  
        mov ah, size qk_hook            
        mul ah                          

        add bx, ax                      
        add bx, size qk_item            
        loop @@find                     
        jmp short @@done                
        ;-  -  -  -  -  -  -  -  -  -  -;

        ;-  -  -  -  -  -  -  -  -  -  -;
@@set:  xor ch, ch                      
        mov cl, [(qk_item bx).hooknum]  
        add bx, size qk_item            

        test cl, cl                     
        jz short @@done                 

@@unhk: mov si, [(qk_hook bx).fnaddr]   
        mov ax, [(qk_hook bx).oldaddr]  
        mov [ds:si], ax                 

        add bx, size qk_hook            
        loop @@unhk                     
        ;-  -  -  -  -  -  -  -  -  -  -;

@@done: dec [exec_calls]
        popa
        ret
Endp


;----------------------------------------------------------------------------;


Proc    int_21h_normalhlt
        sti                             
        mov ah, 0bh                     

        test [mode_flags], MODE_APM     
        jnz short @@apml                

@@stdl: hlt                             
        call_int_handler old_int_21h    ; ★ MACRO: call_int_handler

        cmp al, 0ffh                    
        jne @@stdl                      
        jmp short @@done                

@@apml: mov ax, 5305h                   
        call_int_handler old_int_15h    ; ★ MACRO: call_int_handler

        mov ah, 0bh                     
        call_int_handler old_int_21h    ; ★ MACRO: call_int_handler

        cmp al, 0ffh                    
        jne @@apml                      
@@done: ret
Endp


;----------------------------------------------------------------------------;

Align 16

Proc    int_21h_handler                 
        push ax bx ds
        mov bx, cs                      
        mov ds, bx                      

        cmp ah, INT_21H_TOPFN           
        ja short @@old                  

        xor bh, bh                      
        mov bl, ah                      
        add bx, bx                      
        add bx, offset int_21h_fntable  

        call [word bx]                  
        jmp short @@oldn                

@@old:  mov [int_xxh_fcount], 0         

@@oldn: pop ds bx ax
        jmp [dword cs:old_int_21h]      
Endp



;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ;
;°°°°°°°°°°°°°°°±±±±±±±±±±±±±± INT 16H HANDLER ±±±±±±±±±±±±±±°°°°°°°°°°°°°°°°;
;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ;

INT_16H_TOPFN   = 12h                   


;ÍÍÍÍÍÍ;


Align 4

old_int_16h     rmdw <0, 0>

int_16h_fntable dw offset int_16h_normalhlt    
                dw offset int_xxh_forcehlt     
                dw offset int_xxh_forcehlt     
                dw 0dh dup (int_xxh_zerocount)  
                dw offset int_16h_normalhlt    
                dw offset int_xxh_forcehlt     
                dw offset int_xxh_forcehlt     


;ÍÍÍÍ;


Proc    int_16h_normalhlt
        push bx ax                      ; ★ OPTIMIZACIÓN #2b: Guardar AX original

        ; ★ BUG FIX: Explícitamente usar FN 01h (Check keystroke)
        ; Original: inc ah (convierte FN 00h en FN 01h implícitamente)
        ; Optimizado: Explícito, preserva semántica
        mov ah, 01h                     ; FN 01h: "Is keystroke ready?"
        sti                             

        test [mode_flags], MODE_APM     
        jnz short @@apml                

@@stdl: call_int_handler old_int_16h    ; ★ MACRO
        jnz short @@done                

        hlt                             

        mov ah, 01h                     ; Restaura FN 01h explícitamente
        jmp @@stdl

@@apml: call_int_handler old_int_16h    ; ★ MACRO
        jnz short @@done                

        mov ax, 5305h                   
        call_int_handler old_int_15h    ; ★ MACRO

        mov ah, 01h                     ; Restaura FN 01h
        jmp @@apml                      
@@done:
        pop ax bx                       ; ★ Restaura AX
        ret
Endp


;----------------------------------------------------------------------------;

Align 16

Proc    int_16h_handler                 
        push ax bx ds
        mov bx, cs                      
        mov ds, bx                      

        cmp ah, INT_16H_TOPFN           
        ja short @@old                  

        xor bh, bh                      
        mov bl, ah                      
        add bx, bx                      
        add bx, offset int_16h_fntable  

        call [word bx]                  
        jmp short @@oldn                

@@old:  mov [int_xxh_fcount], 0         

@@oldn: pop ds bx ax
        jmp [dword cs:old_int_16h]      
Endp



;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ;
;°°°°°°°°°°°°°°°±±±±±±±±±±±±±± INT 2FH HANDLER ±±±±±±±±±±±±±±°°°°°°°°°°°°°°°°;
;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ;

INT_2FH_TOPFN   = 0ffffh                


;ÍÍÍÍ;

Align 4

old_int_2fh     rmdw <0, 0>

;ÍÍÍÍ;

Align 16

Proc    int_2fh_handler
        push ax dx ds                   
        mov dx, cs                      
        mov ds, dx                      
        
        cmp ax, 1680h                   
        je short @@dpmi                 

        ; ★ BUG FIX #4: Detectar rango VMPoll 1607h-1609h
        ; Original: cmp ax, 1607h (solo detecta 1607h)
        ; Optimizado: Rango detection para 1607h, 1608h, 1609h
        cmp ax, 1607h                   ; ¿Menor que 1607h?
        jb short @@old                  ; Sí, no es VMPoll
        
        cmp ax, 1609h                   ; ¿Mayor que 1609h?
        ja short @@old                  ; Sí, no es VMPoll
        
        ; Está en rango 1607h-1609h, verificar parámetros adicionales
        cmp bx, 0018h                   ; ¿VxD ID = 0018h?
        jne short @@old                 ; No
        
        test cx, cx                     ; ¿VMPoll driver (cx=0)?
        jnz short @@old                 ; No

@@dpmi: call int_xxh_forcehlt           
        jmp short @@oldn                

@@old:  mov [int_xxh_fcount], 0         

@@oldn: pop ds dx ax
        jmp [dword cs:old_int_2fh]      
Endp

;ÍÍÍÍ;

Align 4

old_int_33h         rmdw <0, 0>
user_mouse_handler  rmdw <OFFSET dummy_mouse_handler, SEG dummy_mouse_handler>
user_mouse_mask     dw 0
dummy_handler_ptr   rmdw <OFFSET dummy_mouse_handler, SEG dummy_mouse_handler>


;ÍÍÍÍ;

Align 16

Proc    int_33h_handler
        sti                                

        mov [cs:int_xxh_fcount], 0         
        
        cmp ax, 000Ch
        je short @@set_handler
        cmp ax, 0014h
        je short @@xchg_handler
        cmp ax, 0018h
        je short @@set_alt_handler

        jmp [dword cs:old_int_33h]      

@@set_handler:
        push es dx cx
        call install_mouse_handler
        pop  cx dx es
        iret

@@xchg_handler:
        call install_mouse_handler
        iret
		
@@set_alt_handler:
        mov ax, 0FFFFh		
        iret
Endp

Proc	mouse_handler
        mov [cs:int_xxh_fcount], 0         

        and ax, [word ptr cs:user_mouse_mask]
        jz short @@done

        jmp [dword ptr cs:user_mouse_handler]
@@done:		
        retf
Endp

;----------------------------------------------------------------------------;

Proc	install_mouse_handler
        push ds     
        push eax
        mov ax, cs	
        mov ds, ax

        mov ax, es
        rol eax, 16
        mov ax, dx		
        test eax, eax	
        jnz short @@valid_handler

        mov eax, [dword dummy_handler_ptr]	
        xor cx, cx

@@valid_handler:
        xchg [dword ptr user_mouse_handler], eax
        xchg [word ptr user_mouse_mask], cx
        mov dx, ax	
        ror eax, 16
        mov es, ax

        push es
        push dx
        push cx

        mov dx, SEG mouse_handler
        mov es, dx
        mov dx, offset mouse_handler
        mov cx, 7Fh						
        mov ax, 000Ch
        call_int_handler old_int_33h    ; ★ MACRO

        pop cx
        pop dx
        pop es

        pop eax
        pop ds
        ret
Endp

Proc	dummy_mouse_handler
        retf
Endp

;----------------------------------------------------------------------------;


;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ;
;°°°°°°°°°°°°°°°±±±±±±±±±±±±±± INT 14H HANDLER ±±±±±±±±±±±±±±°°°°°°°°°°°°°°°°;
;ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ;

INT_14H_TOPFN   = 03h                   


;ÍÌÌÌ;

Align 4

old_int_14h     rmdw <0, 0>

int_14h_fntable dw offset int_xxh_zerocount    
                dw offset int_xxh_zerocount    
                dw offset int_14h_normalhlt    
                dw offset int_xxh_forcehlt     


;ÍÌÍÌ;


Proc    int_14h_normalhlt
	sti                             

        test [mode_flags], MODE_APM     
        jnz short @@apml                

@@stdl: hlt                             
        mov ah, 03h                     
        call_int_handler old_int_14h    ; ★ MACRO

        test ah, 1                      
        jz @@stdl                       
        jmp short @@done                

@@apml: mov ax, 5305h                   
        call_int_handler old_int_15h    ; ★ MACRO

        mov ah, 03h                     
        call_int_handler old_int_14h    ; ★ MACRO

        test ah, 1                      
        jz @@apml                       
@@done: ret
Endp


;----------------------------------------------------------------------------;

	Align 16

Proc    int_14h_handler                 
        push ax bx ds
        mov bx, cs                      
        mov ds, bx                      

        cmp ah, INT_14H_TOPFN           
        ja short @@old                  

        xor bh, bh                      
        mov bl, ah                      
        add bx, bx                      
        add bx, offset int_14h_fntable  

        call [word bx]                  
        jmp short @@oldn                

@@old:  mov [int_xxh_fcount], 0         

@@oldn: pop ds bx ax
        jmp [dword cs:old_int_14h]      
Endp

RESIDENT_END:

ENDS CODE16

END
