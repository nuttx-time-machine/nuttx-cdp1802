# 8. The interfaces in include/nuttx/arch.h

> First tag: `step-05-skeleton`. Generated from `include/nuttx/arch.h` at the
> pinned NuttX commit (`c7080cbdfe`) by the script in the Step 05 journal;
> regenerate it when NuttX moves.

`include/nuttx/arch.h` is the authoritative list of what an architecture
provides (read it at *your* commit: it changes). `include/nuttx/board.h`
lists the board hooks (e.g. `board_late_initialize()`, which our link also
required).

**How to find out what *you* must implement:** build a minimal configuration
with no arch code at all and read the linker's `undefined reference to up_...`
list (chapter 2). Everything else is either inline in a header, optional, or
needed only with certain Kconfig options. The "Declared under" column gives
the preprocessor condition around the prototype.

> **CDP1802 example:** `sim1802:minimal` needed **16** interfaces to link. They
> are marked "yes (link)" below, plus `board_late_initialize()` from
> `board.h`. At step-05 they are `PANIC()`/empty stubs in `cosmac_stubs.c`.
> The column is updated as Steps 06–09 implement them. The interrupt-state
> functions are real at step-05 (`cosmac_irqsave.S`).

| Interface | Purpose (from arch.h) | Declared under | Needed by `sim1802:minimal` | CDP1802 status (step-05) |
|---|---|---|---|---|
| `arch_phy_irq` | This function may be called to register an interrupt handler that will be called when a PHY interrupt occurs. | `(macro or not a prototype)` |  |  |
| `arch_sporadic_` | Hooks that can be enabled to monitor the behavior of the sporadic scheduler. | `(macro or not a prototype)` |  |  |
| `irq_dispatch` | This function must be called from the architecture-specific logic in order to dispatch an interrupt to the appropriate, registered handling  | `(macro or not a prototype)` |  |  |
| `nxsched_process_cpuload_ticks` | Collect data that can be used for CPU load measurements. | `(macro or not a prototype)` |  |  |
| `nxsched_process_timer` | This function handles system timer events (only when CONFIG_SCHED_TICKLESS is *not* defined). | `(macro or not a prototype)` |  |  |
| `pgalloc` | If there is a page allocator in the configuration and if an MMU is available to map physical addresses to virtual address, then this functio | `(macro or not a prototype)` |  |  |
| `up_addrenv_attach` | This function is called from the core scheduler logic when a thread is created that needs to share the address environment of its task group | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_clone` | Duplicate an address environment. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_coherent` | Flush D-Cache and invalidate I-Cache in preparation for a change in address environments. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_create` | This function is called when a new task is created in order to instantiate an address environment for the new task group. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_destroy` | This function is called when a final thread leaves the task group and the task group is destroyed. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_detach` | This function is called when a task or thread exits in order to release its reference to an address environment. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_find_page` | Find physical page mapped to user virtual address from the address environment page directory. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_fork` | Duplicate an address environment for POSIX fork():  allocate fresh pages for the destination, copy the source's contents into them, and map  | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_FORK)` |  |  |
| `up_addrenv_heapsize` | Return the initial heap allocation size. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV) && de` |  |  |
| `up_addrenv_kmap_init` | Initialize the architecture specific part of the kernel mapping interface. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV) && de` |  |  |
| `up_addrenv_kmap_pages` | Map physical pages into a continuous virtual memory block. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV) && de` |  |  |
| `up_addrenv_kstackalloc` | This function is called when a new thread is created to allocate the new thread's kernel stack. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV) && de` |  |  |
| `up_addrenv_kstackfree` | This function is called when any thread exits. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV) && de` |  |  |
| `up_addrenv_kunmap_pages` | Unmap a previously mapped virtual memory region. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV) && de` |  |  |
| `up_addrenv_mprot` | Modify access rights to an address range. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_pa_to_va` | Map phy address to virtual address. | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_addrenv_page_vaddr` | Find the kernel virtual address associated with physical page. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_page_wipe` | Wipe a page of physical memory, first mapping it into kernel virtual memory. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_select` | After an address environment has been established for a task group (via up_addrenv_create(). | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_user_vaddr` | Check if a virtual address is in user virtual address space. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_ustackalloc` | This function is called when a new thread is created in order to instantiate an address environment for the new thread's stack. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV) && de` |  |  |
| `up_addrenv_ustackfree` | This function is called when any thread exits. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV) && de` |  |  |
| `up_addrenv_ustackselect` | After an address environment has been established for a task's stack (via up_addrenv_ustackalloc(). | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV) && de` |  |  |
| `up_addrenv_va_to_pa` | Map virtual address to phy address. | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_addrenv_vdata` | Return the virtual address associated with the newly create .text address environment. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_vheap` | Return the heap virtual address associated with the newly created address environment. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV) && de` |  |  |
| `up_addrenv_vtext` | Return the virtual address associated with the newly create .text address environment. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV)` |  |  |
| `up_addrenv_vustack` | Return the virtual address associated with the newly create stack address environment. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ADDRENV) && de` |  |  |
| `up_adjtime` |  | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_ADJTIME)` |  |  |
| `up_affinity_irq` | Set an IRQ affinity by software. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_SMP)` |  |  |
| `up_alarm_cancel` | Cancel the alarm and return the time of cancellation of the alarm. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_SCHED_TICKLESS) && ` |  |  |
| `up_alarm_start` | Start the alarm. | `!defined(__INCLUDE_NUTTX_ARCH_H) && (defined(CONFIG_HRTIMER) && define` |  |  |
| `up_alarm_tick_cancel` |  | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_SCHED_TICKLESS) && ` |  |  |
| `up_alarm_tick_start` |  | `!defined(__INCLUDE_NUTTX_ARCH_H) && (defined(CONFIG_HRTIMER) && define` |  |  |
| `up_alloc_irq_msi` | Allocate interrupts for MSI/MSI-X vector. | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_allocate_heap` | This function will be called to dynamically set aside the heap region. | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_allocate_kheap` | For the kernel builds (CONFIG_BUILD_PROTECTED=y or CONFIG_BUILD_KERNEL=y) there may be both kernel- and user-space heaps as determined by CO | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_MM_KERNEL_HEAP)` |  |  |
| `up_allocate_pgheap` | If there is a page allocator in the configuration, then this function must be provided by the platform-specific code. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_MM_PGALLOC)` |  |  |
| `up_assert` |  | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_SYSCALL)` |  |  |
| `up_backtrace` | up_backtrace()  returns  a backtrace for the TCB, in the array pointed to by buffer. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_BACKTRACE` |  |  |
| `up_check_intstack` |  | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_STACK_COLORATION) &` |  |  |
| `up_check_tcbstack` | Determine (approximately) how much stack has been used be searching the stack memory for a high water mark. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_STACK_COLORATION)` |  |  |
| `up_connect_irq` | Connect interrupt for MSI/MSI-X. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_PCI)` |  |  |
| `up_copy_section` | This function copies a section from a general temporary buffer (src) to a specific address (dest). | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_USE_COPY_SECTI` |  |  |
| `up_cpu_idlestack` | Allocate a stack for the CPU[n] IDLE task (n > 0) if appropriate and setup up stack-related information in the IDLE task's TCB. | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_cpu_index` | Return the real core number regardless CONFIG_SMP setting | `(macro or not a prototype)` |  |  |
| `up_cpu_start` | In an SMP configuration, only one CPU is initially active (CPU 0). | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_SMP)` |  |  |
| `up_create_stack` | Allocate a stack for a new thread and setup up stack-related information in the TCB. | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_dataheap_free` | Free memory allocated for data sections. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_USE_DATA_HEAP)` |  |  |
| `up_dataheap_heapmember` | Test if memory is from data heap. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_USE_DATA_HEAP)` |  |  |
| `up_dataheap_memalign` | Allocate memory for data with the specified alignment and sectname. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_USE_DATA_HEAP)` |  |  |
| `up_debugpoint_add` | Add a debugpoint. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_DEBUG)` |  |  |
| `up_debugpoint_remove` | Remove a debugpoint. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_DEBUG)` |  |  |
| `up_disable_irq` | This function implements disabling of the device specified by 'irq' at the interrupt controller level if supported by the architecture (up_i | `!defined(__INCLUDE_NUTTX_ARCH_H) && !defined(CONFIG_ARCH_NOINTC)` |  |  |
| `up_dump_register` | Register dump may be handled in an architecture-specific way. | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_enable_irq` | On many architectures, there are three levels of interrupt enabling: (1) at the global level, (2) at the level of the interrupt controller,  | `!defined(__INCLUDE_NUTTX_ARCH_H) && !defined(CONFIG_ARCH_NOINTC)` |  |  |
| `up_exit` | This function causes the currently executing task to cease to exist. | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_extraheaps_init` | Initialize any extra heap. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_EXTRA_HEA` |  |  |
| `up_fork` | Architecture-specific base of both cloning primitives. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_VFORK) ||` |  |  |
| `up_fpucmp` | Compare FPU areas from thread context. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_FPU)` |  |  |
| `up_get_intstackbase` |  | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_INTERRUPTSTACK` |  |  |
| `up_get_legacy_irq` | Reserve vector for legacy | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_PCI)` |  |  |
| `up_getsp` |  | `(macro or not a prototype)` |  |  |
| `up_getusrsp` |  | `(macro or not a prototype)` |  |  |
| `up_idle` | up_idle() is the logic that will be executed when there is no other ready-to-run task. | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_initial_state` | A new thread is being started and a new TCB has been created. | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_initialize` | up_initialize will be called once during OS initialization after the basic OS services have been initialized. | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_irq_to_ndx` | Irq to ndx | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_IRQ_TO_NDX)` |  |  |
| `up_irqinitialize` |  | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_lowputc` | Output one character in early boot-stages. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_LOWPUTC)` |  |  |
| `up_mdelay` | Some device drivers may require that the platform-specific logic provides these timing loops for short delays. | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_memtag_bypass` | Set MTE state bypass or not | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_MEMTAG)` |  |  |
| `up_memtag_get_random_tag` | Get a random label based on the address through the mte register | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_MEMTAG)` |  |  |
| `up_memtag_get_tag` |  | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_MEMTAG)` |  |  |
| `up_memtag_set_tag` | Get the address with label | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_MEMTAG)` |  |  |
| `up_memtag_tag_mem` | Set memory tags for a given memory range | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_MEMTAG)` |  |  |
| `up_ndelay` |  | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_nputs` |  | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_perf_` | The first interface simply provides the current time value in unknown units. | `(macro or not a prototype)` |  |  |
| `up_perf_convert` |  | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_perf_getfreq` |  | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_perf_gettime` |  | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_perf_init` |  | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_prioritize_irq` | Set the priority of an IRQ. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_IRQPRIO)` |  |  |
| `up_pthread_start` | In this kernel mode build, this function will be called to execute a pthread in user-space. | `!defined(__INCLUDE_NUTTX_ARCH_H) && !defined(CONFIG_BUILD_FLAT) && def` |  |  |
| `up_putc` | Output one character on the console | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_puts` | Output a string on the console | `(macro or not a prototype)` |  |  |
| `up_regs_memcpy` |  | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_REGCPY)` |  |  |
| `up_release_irq_msi` | Allocate interrupts for MSI/MSI-X vector. | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_release_stack` | A task has been stopped. | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_romgetc` | In Harvard architectures, data accesses and instruction accesses occur on different buses, perhaps concurrently. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_ROMGETC)` |  |  |
| `up_rtc_adjtime` | Adjust RTC frequency (running rate). | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_RTC_HIRES) && defin` |  |  |
| `up_rtc_getdatetime` | Get the current date and time from the date/time RTC. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_RTC) && defined(CON` |  |  |
| `up_rtc_getdatetime_with_subseconds` | Get the current date and time from the date/time RTC. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_RTC) && defined(CON` |  |  |
| `up_rtc_gettime` | Get the current time from the high resolution RTC clock/counter. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_RTC) && defined(CON` |  |  |
| `up_rtc_initialize` | Initialize the builtin, MCU hardware RTC per the selected configuration. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_RTC)` |  |  |
| `up_rtc_settime` | Set the RTC to the provided time. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_RTC)` |  |  |
| `up_rtc_time` | Get the current time in seconds. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_RTC) && !defined(CO` |  |  |
| `up_saveusercontext` | Save the current thread context | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_schedule_sigaction` | This function is called by the OS when one or more signal handling actions have been queued for execution. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ENABLE_ALL_SIGNALS)` |  |  |
| `up_secure_irq` | Secure an IRQ | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_TRUSTZONE_SECU` |  |  |
| `up_secure_irq_all` | Secure all IRQ | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_TRUSTZONE_SECU` |  |  |
| `up_send_smp_call` | Send smp call to target cpu | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_SMP)` |  |  |
| `up_send_smp_sched` | pause task execution on the CPU check whether there are tasks delivered to specified cpu and try to run them. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_SMP)` |  |  |
| `up_set_irq_type` | Config an IRQ trigger type. | `!defined(__INCLUDE_NUTTX_ARCH_H) && !defined(CONFIG_ARCH_NOINTC)` |  |  |
| `up_setpicbase` | It NXFLAT external modules (or any other binary format that requires PIC) are supported, then these macros must defined to (1) set or get th | `(macro or not a prototype)` |  |  |
| `up_shmat` | Attach, i.e, map, on shared memory region to a user virtual address | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_VMA_MAPPING)` |  |  |
| `up_shmdt` | Detach, i.e, unmap, on shared memory region from a user virtual address | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_VMA_MAPPING)` |  |  |
| `up_show_cpuinfo` | This function will be called when reading /proc/cpufinfo. | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_signal_dispatch` | In this kernel mode build, this function will be called to execute a a signal handler in user-space. | `!defined(__INCLUDE_NUTTX_ARCH_H) && !defined(CONFIG_BUILD_FLAT) && def` |  |  |
| `up_signal_handler` | This function is the user-space, signal handler trampoline function that must be provided by architecture-specific logic. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_BUILD_PROTECTED) &&` |  |  |
| `up_stack_frame` | Allocate a stack frame in the TCB's stack to hold thread-specific data. | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_switch_context` | A task is currently in the ready-to-run list but has been prepped to execute. | `!defined(__INCLUDE_NUTTX_ARCH_H) && !defined(up_switch_context)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_systempoweroff` | The function up_systempoweroff() will power down the MCU. | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_systemreset` | The function up_systemreset() will reset the MCU. | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_task_start` | In this kernel mode build, this function will be called to execute a task in user-space. | `!defined(__INCLUDE_NUTTX_ARCH_H) && !defined(CONFIG_BUILD_FLAT) && def` |  |  |
| `up_textheap_data_address` | If an instruction bus address is specified, return the corresponding data bus address. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_USE_TEXT_HEAP)` |  |  |
| `up_textheap_data_sync` | Ensure modifications made on the data bus addresses (the addresses returned by up_textheap_data_address) fully visible on the corresponding  | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_USE_TEXT_HEAP)` |  |  |
| `up_textheap_free` | Free memory allocated for text sections. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_USE_TEXT_HEAP)` |  |  |
| `up_textheap_heapmember` | Test if memory is from text heap. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_USE_TEXT_HEAP)` |  |  |
| `up_textheap_memalign` | Allocate memory for text with the specified alignment and sectname. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_USE_TEXT_HEAP)` |  |  |
| `up_this_cpu` | Return the logical core number. | `(macro or not a prototype)` |  |  |
| `up_timer_cancel` | Cancel the interval timer and return the time remaining on the timer. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_SCHED_TICKLESS) && ` |  |  |
| `up_timer_getmask` |  | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_timer_gettick` |  | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_timer_gettime` | Return the elapsed time since power-up (or, more correctly, since the architecture-specific timer was initialized). | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_timer_initialize` |  | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |
| `up_timer_start` | Start the interval timer. | `!defined(__INCLUDE_NUTTX_ARCH_H) && (defined(CONFIG_HRTIMER) && define` |  |  |
| `up_timer_tick_cancel` |  | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_SCHED_TICKLESS) && ` |  |  |
| `up_timer_tick_start` |  | `!defined(__INCLUDE_NUTTX_ARCH_H) && (defined(CONFIG_HRTIMER) && define` |  |  |
| `up_tls_info` | Return the TLS information structure for the currently executing thread. | `(macro or not a prototype)` |  |  |
| `up_tls_initialize` | Initialize thread local region | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_SCHED_THREAD_LOCAL)` |  |  |
| `up_tls_size` | Get TLS (sizeof(struct tls_info_s) + tdata + tbss) section size. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_SCHED_THREAD_LOCAL)` |  |  |
| `up_trigger_irq` | Trigger an IRQ by software. | `!defined(__INCLUDE_NUTTX_ARCH_H) && defined(CONFIG_ARCH_HAVE_IRQTRIGGE` |  |  |
| `up_udelay` |  | `!defined(__INCLUDE_NUTTX_ARCH_H)` |  |  |
| `up_update_task` | We can utilize percpu storage to hold information about the current running task. | `(macro or not a prototype)` |  |  |
| `up_use_stack` | Setup stack-related information in the TCB using pre-allocated stack memory. | `!defined(__INCLUDE_NUTTX_ARCH_H)` | **yes (link)** | stub (`cosmac_stubs.c`) |

## Checklist

- [ ] You have the linker's list of required interfaces for your minimal
      configuration.
- [ ] You know, for each Kconfig feature you plan to enable, which extra
      interfaces it requires (the "Declared under" column).

## Common pitfalls

- Implementing interfaces from memory of an older NuttX: names and
  signatures change (e.g. `up_switch_context(tcb, rtcb)` takes two TCBs at
  this commit).
- Empty stubs that silently do nothing where NuttX expects an effect. Prefer
  `PANIC()` until the real code exists.
