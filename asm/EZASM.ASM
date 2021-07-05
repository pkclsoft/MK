*                              EZASM.ASM
*
* This unit contains routines for the manipulation of strings.
*
* Copyright 1989...End Of Time
* EZ-Soft
*
* Written by: P.C. Easdown

         absaddr on
         keep EZAsm

         mload asm/EZAsm.Macros
         copy 13/ainclude/e16.quickdraw
         copy 13/ainclude/e16.resources

ULongAdd start

result   equ    0

         subroutine (4:val1,4:val2),4
         
         longa  on
         clc
         lda    val1
         adc    val2
         sta    result
         lda    val1+2
         adc    val2+2
         sta    result+2
         
         return 4:result
         
         end

ULongSub start

result   equ    0

         subroutine (4:val1,4:val2),4
         
         longa  on
         
         sec
         lda    val1
         sbc    val2
         sta    result
         lda    val1+2
         sbc    val2+2
         sta    result+2
         
         return 4:result
         
         end
         
         
Upper    start

         subroutine (2:InChar),2

OutChar  equ   0

         lda   #$0000

         shortm

         lda   InChar
         cmp   #'a'
         bmi   Done
         cmp   #'z'+1
         bpl   Done
         and   #$5f

Done     sta   OutChar

         longm

         Return 2:OutChar

         end

; Will convert a pascal type string to uppercase.

UpperStr start

         subroutine (4:StrPtr),0

         lda   #$0000

         shortm

         lda   [StrPtr]
         beq   Done
         tay

DoChar   lda   [StrPtr],y
         cmp   #'a'
         bmi   NextChar
         cmp   #'z'+1
         bpl   NextChar
         and   #$5f
         sta   [StrPtr],y

NextChar dey
         bne   DoChar

Done     longm

         Return

         end

Lower    start

         subroutine (2:InChar),2

OutChar  equ   0

         lda   #$0000

         shortm

         lda   InChar
         cmp   #'A'
         bmi   Done
         cmp   #'Z'+1
         bpl   Done
         ora   #$20

Done     sta   OutChar

         longm

         Return 2:OutChar

         end

; Will convert a pascal type string to lowercase.

LowerStr start

         subroutine (4:StrPtr),0

         lda   #$0000

         shortm

         lda   [StrPtr]
         beq   Done
         tay

DoChar   lda   [StrPtr],y
         cmp   #'A'
         bmi   NextChar
         cmp   #'Z'+1
         bpl   NextChar
         ora   #$20
         sta   [StrPtr],y

NextChar dey
         bne   DoChar

Done     longm

         Return

         end
