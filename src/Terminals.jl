module Terminals
    import Base.size, Base.write, Base.flush
    abstract TextTerminal <: Base.IO
    export TextTerminal, NCurses, writepos, cmove, pos, getX, getY

    # Stuff that really should be in a Geometry package
    immutable Rect
        top
        left
        width
        height
    end

    immutable Size
        width
        height
    end 


    # INTERFACE
    size(::TextTerminal) = error("Unimplemented")
    writepos(t::TextTerminal,x,y,s::Array{Uint8,1}) = error("Unimplemented")
    cmove(t::TextTerminal,x,y) = error("Unimplemented")
    getX(t::TextTerminal) = error("Unimplemented")
    getY(t::TextTerminal) = error("Unimplemented")
    pos(t::TextTerminal) = (getX(t),getY(t))

    # Relative moves (Absolute position fallbacks)
    export cmove_up, cmove_down, cmove_left, cmove_right, cmove_line_up, cmove_line_down, cmove_col

    cmove_up(t::TextTerminal,n) = cmove(getX(),max(1,getY()-n))
    cmove_up(t) = cmove_up(t,1)

    cmove_down(t::TextTerminal,n) = cmove(getX(),max(height(t),getY()+n))
    cmove_down(t) = cmove_down(t,1)

    cmove_left(t::TextTerminal,n) = cmove(max(1,getX()-n),getY())
    cmove_left(t) = cmove_left(t,1)

    cmove_right(t::TextTerminal,n) = cmove(max(width(t),getX()+n),getY())
    cmove_right(t) = cmove_right(t,1)

    cmove_line_up(t::TextTerminal,n) = cmove(1,max(1,getY()-n))
    cmove_line_up(t) = cmove_line_up(t,1)

    cmove_line_down(t::TextTerminal,n) = cmove(1,max(height(t),getY()+n))
    cmove_line_down(t) = cmove_line_down(t,1)

    cmove_col(t::TextTerminal,c) = comve(c,getY())

    # Defaults
    hascolor(::TextTerminal) = false

    # Utility Functions
    function write{T}(t::TextTerminal, b::Array{T})
        if isbits(T)
            write(t,reinterpret(Uint8,b))
        else
            invoke(write, (IO, Array), s, a)
        end
    end
    function writepos{T}(t::TextTerminal, x, y, b::Array{T})
        if isbits(T)
            writepos(t,x,y,reinterpret(Uint8,b))
        else
            cmove(t,x,y)
            invoke(write, (IO, Array), s, a)
        end
    end
    function writepos(t::TextTerminal,x,y,args...)
        cmove(t,x,y)
        write(t,args...)
    end 
    width(t::TextTerminal) = size(t).width
    height(t::TextTerminal) = size(t).height

    # For terminals with buffers
    flush(t::TextTerminal) = nothing

    clear(t::TextTerminal) = error("Unimplemented")
    clear_line(t::TextTerminal,row) = error("Unimplemented")
    clear_line(t::TextTerminal) = error("Unimplemented")

    raw!(t::TextTerminal,raw::Bool) = error("Unimplemented")

    beep(t::TextTerminal) = nothing

    abstract TextAttribute

    module Attributes
        # This is just to get started and will have to be revised

        import Terminals.TextAttribute, Terminals.TextTerminal

        export Standout, Underline, Reverse, Blink, Dim, Bold, AltCharset, Invisible, Protect, Left, Right, Top,
                Vertical, Horizontal, Low

        macro flag_attribute(name)
            quote
                immutable $name <: TextAttribute
                end
            end
        end

        @flag_attribute Standout
        @flag_attribute Underline
        @flag_attribute Reverse
        @flag_attribute Blink
        @flag_attribute Dim
        @flag_attribute Bold
        @flag_attribute AltCharset
        @flag_attribute Invisible
        @flag_attribute Protect
        @flag_attribute Left
        @flag_attribute Right
        @flag_attribute Top
        @flag_attribute Vertical
        @flag_attribute Horizontal
        @flag_attribute Low

        attr_simplify(::TextTerminal, x::TextAttribute) = x
        attr_simplify{T<:TextAttribute}(::TextTerminal, ::Type{T}) = T()
        function attr_simplify(::TextTerminal, s::Symbol)
            if s == :standout 
                return Standout()
            elseif s == :underline 
                return Underline()
            elseif s == :reverse 
                return Reverse()
            elseif s == :blink
                return Blink()
            end
        end


    end

    module Colors 
        import Terminals.TextAttribute, Terminals.TextTerminal, Terminals.Attributes.attr_simplify
        using Color

        export TerminalColor, TextColor, BackgroundColor, ForegroundColor, approximate,
                lookup_color, terminal_color, maxcolors, maxcolorpairs, palette, numcolors

        # Represents a color actually displayable by the current terminal
        abstract TerminalColor

        immutable TextColor <: TextAttribute
            c::TerminalColor
        end
        immutable BackgroundColor <: TextAttribute
            c::TerminalColor
        end

        function approximate(t::TextTerminal, c::ColorValue)
            x = keys(palette(t))
            lookup_color(t,x[indmin(map(x->colordiff(c,x),x))])
        end

        attr_simplify(t::TextTerminal, c::ColorValue) = TextColor(lookup_color(t,c))

        # Terminals should implement this
        lookup_color(t::TextTerminal) = error("Unimplemented")
        maxcolors(t::TextTerminal) = error("Unimplemented")
        maxcolorpairs(t::TextTerminal) = error("Unimplemented")
        palette(t::TextTerminal) = error("Unimplemented")
        numcolors(t::TextTerminal) = error("Unimplemented")
    end

    # Unix Terminals
    module NCurses
        importall Terminals
        using Terminals.Colors
        using Terminals.Attributes

        import Terminals.width, Terminals.height, Terminals.cmove, Terminals.Rect, Terminals.Size, 
               Terminals.getX, Terminals.getY, Terminals.TextAttribute, Terminals.Attributes.attr_simplify
        import Base.size, Base.write, Base.flush

        abstract NCursesSurface <: TextTerminal

        export clear, move, Window, Terminal, touch

        global curses_colors

        ncurses_h = dlopen("libncurses")
        
        # Libraries
        const ncurses = :libncurses
        const panel = :libpanel

        type Terminal <: NCursesSurface
            auto_flush::Bool
            onkey_cbs::Array{Function,1}
            screen::Ptr{Void}

            function Terminal(auto_flush::Bool,raw::Bool,termtype,ofp,ifp)
                screen = ccall((:newterm,ncurses),Ptr{Void},(Ptr{Uint8},Ptr{Void},Ptr{Void}),termtype,ofp,ifp)
            end

            function Terminal(auto_flush::Bool,raw::Bool)
                ccall((:savetty, ncurses), Void, ())
                atexit() do 
                    #ccall((:resetty, ncurses), Void, ())
                    ccall((:endwin, ncurses), Void, ())
                end
                ccall((:initscr, ncurses), Void, ())
                if(raw)
                    ccall((:raw, ncurses), Void, ())
                end

                t = new(auto_flush,Array(Function,0))
                if hascolor(t)
                    ccall((:start_color,ncurses),Void,())
                end

                if false
                fdw = FDWatcher(OS_FD(int32(0)))
                start_watching(fdw,UV_READABLE) do status, events
                    if status != -1
                        x = ccall((:wgetch,ncurses),Int32,(Ptr{Void},),stdscr(t).handle)
                        if x != -1
                            for f in t.onkey_cbs
                                if f(x)
                                    break
                                end
                            end
                        end
                    end
                end
                end

                ccall((:nodelay,ncurses),Int32,(Ptr{Void},Int32),stdscr(t).handle,1)
                ccall((:cbreak,ncurses),Void,())
                ccall((:noecho,ncurses),Void,())
                t
            end
            Terminal() = Terminal(true,false)

        end

        ## NCurses C Windows type - currently not used but useful for debugging ##
        typealias curses_size_t Cshort
        typealias curses_attr_t Cint
        typealias curses_chtype Cuint
        typealias curses_bool Uint8

        type C_NCursesWindow 
            curY::curses_size_t         # Current X Cursor
            curX::curses_size_t         # Current Y Cursor
            maxY::curses_size_t
            maxX::curses_size_t
            begY::curses_size_t
            begX::curses_size_t
            flags::Cshort               # Window State Flags
            attrs::curses_attr_t
            notimeout::curses_bool
            clear::curses_bool
            scroll::curses_bool
            idlok::curses_bool
            idcok::curses_bool
            immed::curses_bool
            use_keypad::curses_bool
            delay::Cint
            ldat::Ptr{Void}
            regtop::curses_size_t
            regbottom::curses_size_t
            parx::Cint
            pary::Cint
            parent::Ptr{C_NCursesWindow}
            pad_y::curses_size_t
            pad_x::curses_size_t
            pad_top::curses_size_t
            pad_left::curses_size_t
            pad_bottom::curses_size_t
            pad_right::curses_size_t
            yoffset::curses_size_t
        end

        immutable Window <: NCursesSurface
            auto_flush::Bool
            handle::Ptr{Void}
            Window(handle::Ptr{Void}) = new(true, handle)
            Window(parent::Terminal,auto_flush::Bool,dim::Rect) = Window(stdscr(parent),auto_flush::Bool,dim::Rect) 
            function Window(parent::Window,auto_flush::Bool,dim::Rect) 
                new(auto_flush,ccall((:subwin,ncurses),Ptr{Void},(Ptr{Void},Int32,Int32,Int32,Int32),parent.handle,dim.height,dim.width,dim.top,dim.left))
            end
            Window(auto_flush::Bool,dim::Rect) = new(auto_flush,ccall((:newwin,ncurses),Ptr{Void},(Int32,Int32,Int32,Int32),dim.height,dim.width,dim.top,dim.left))
            Window(parent::NCursesSurface,auto_flush,height,width,left,top) = Window(parent,auto_flush,Rect(top,left,width,height))
            Window(auto_flush,height,width,left,top) = Window(auto_flush,Rect(top,left,width,height))
            Window(dim::Rect) = Window(true,dim)
            Window(height,width,left,top) = Window(true,height,width,left,top)
        end

        flush(w::Window) = ccall((:wrefresh,ncurses),Void,(Ptr{Void},),w.handle)
        touch(w::Window) = ccall((:touchwin,ncurses),Void,(Ptr{Void},),w.handle)

        macro writefunc(t,expr)
            quote
                $(esc(expr))
                if ($(esc(t)).auto_flush)
                    flush($(esc(t)))
                end
            end
        end

        
        hascolor(t::Terminal) = ccall((:has_colors,ncurses),Int32,()) != 0
        hascolor(w::Window) = ccall((:has_colors,ncurses),Int32,()) != 0

        # Character Attributes
        attr(::ANY) = 0
        attr(::Standout)   = uint32(1)<<(8+8)
        attr(::Underline)  = uint32(1)<<(8+9)
        attr(::Reverse)    = uint32(1)<<(8+10)
        attr(::Blink)      = uint32(1)<<(8+11)
        attr(::Dim)        = uint32(1)<<(8+12)
        attr(::Bold)       = uint32(1)<<(8+13)
        attr(::AltCharset) = uint32(1)<<(8+14)
        attr(::Invisible)  = uint32(1)<<(8+15)
        attr(::Protect)    = uint32(1)<<(8+16)
        attr(::Horizontal) = uint32(1)<<(8+17)
        attr(::Left)       = uint32(1)<<(8+18)
        attr(::Low)        = uint32(1)<<(8+19)
        attr(::Right)      = uint32(1)<<(8+20)
        attr(::Top)        = uint32(1)<<(8+21)
        attr(::Vertical)   = uint32(1)<<(8+22)

        immutable CustomAttribute <: TextAttribute
            flag::Int32
            CustomAttribute(flag::Integer) = new(int32(flag))
        end

        attr(c::CustomAttribute) = c.flag


        # Ideally this would use a ccall-like API. Do we have that?
        const stdscr_symb = convert(Ptr{Ptr{Void}},dlsym(ncurses_h,:stdscr))
        const curscr_symb = convert(Ptr{Ptr{Void}},dlsym(ncurses_h,:curscr))
        const COLORS_symb = convert(Ptr{Int32},dlsym(ncurses_h,:COLORS))
        const COLOR_PAIRS_symb = convert(Ptr{Int32},dlsym(ncurses_h,:COLOR_PAIRS))

        stdscr(::Terminal) = Window(unsafe_load(stdscr_symb))
        curscr(::Terminal) = Window(unsafe_load(curscr_symb))
        maxcolors(::Terminal) = unsafe_load(COLORS_symb)
        maxcolorpairs(::Window) = unsafe_load(COLOR_PAIRS_symb)

        # write
        write(t::Terminal, c::Uint8) = @writefunc t ccall((:addch,ncurses),Int32,(curses_chtype,),c)
        write(w::Window, c::Uint8) = @writefunc w ccall((:waddch,ncurses),Int32,(Ptr{Void},curses_chtype),w.handle,c)
        write(t::Terminal, c::Uint8, attributes) = @writefunc t ccall((:addch,ncurses),Int32,(curses_chtype,),c|reduce((|),map(x->(attr(attr_simplify(t,x))),attributes)))
        write(w::Window, c::Uint8, attributes) = @writefunc w ccall((:waddch,ncurses),Int32,(Ptr{Void},curses_chtype),w.handle,c|reduce((|),map(x->(attr(attr_simplify(w,x))),attributes)))
        write(t::Terminal, b::Array{Uint8,1}) = @writefunc t ccall((:addnstr,ncurses),Int32,(Ptr{Uint8},Int32),b,length(b))
        write(w::Window, b::Array{Uint8,1}) = @writefunc w ccall((:waddnstr,ncurses),Int32,(Ptr{Void},Ptr{Uint8},Int32),w.handle,b,length(b))
        write(w::Terminal, p::Ptr{Uint8}, n) = @writefunc w ccall((:addnstr,ncurses),Int32,(Ptr{Void},Ptr{Uint8},Int32),p,n)
        write(w::Window, p::Ptr{Uint8}, n) = @writefunc w ccall((:waddnstr,ncurses),Int32,(Ptr{Void},Ptr{Uint8},Int32),w.handle,p,n)


        # writepos
        writepos(t::Terminal, x, y, c::Uint8) = @writefunc t ccall((:addch,ncurses),Int32,(Int32,Int32,curses_chtype,),x,y,c)
        writepos(w::Window, x, y, c::Uint8) = @writefunc w ccall((:waddch,ncurses),Int32,(Ptr{Void},Int32,Int32,curses_chtype),w.handle,x,y,c)
        writepos(t::Terminal, x, y, b::Array{Uint8,1}) = @writefunc t ccall((:mvaddnstr,ncurses),Int32,(Int32,Int32,Ptr{Uint8},Int32),x,yb,length(b))
        writepos(w::Window, x, y, b::Array{Uint8,1}) = @writefunc w ccall((:waddstr,ncurses),Int32,(Int32,Int32,Ptr{Void},Ptr{Uint8},Int32),w.handle,x,y,b,length(b))

        # cursor move 
        cmove(t::Terminal, x, y) = ccall((:move,ncurses),Void,(Int32,Int32),x,y)
        cmove(w::Window, x, y) = ccall((:wmove,ncurses),Void,(Ptr{Void},Int32,Int32),w.handle,x,y)

        # window move
        move(w::Window, x, y) = ccall((:mvwin,ncurses),Void,(Ptr{Void},Int32,Int32),w.handle,x,y)

        # box
        box!(w::Window) = ccall((:box,ncurses),Int32,(Ptr{Void},curses_chtype,curses_chtype),w.handle,uint8('|'),uint8('-'))

        # clear
        clear(t::Terminal) = ccall((:clear,ncurses),Void,())
        clear(w::Window) = ccall((:wclear,ncurses),Void,(Ptr{Void},),w.handle)

        # position-related
        getX(w::Window) = ccall((:getcurx,ncurses),Int32,(Ptr{Void},),w.handle)
        getX(t::Terminal) = getX(stdscr(t))
        getY(w::Window) = ccall((:getcury,ncurses),Int32,(Ptr{Void},),w.handle)
        getY(t::Terminal) = getX(stdscr(t))

        #size-related 
        width(w::Window) = ccall((:getmaxx,ncurses),Int32,(Ptr{Void},),w.handle)
        width(t::Terminal) = width(stdscr(t))
        height(w::Window) = ccall((:getmaxy,ncurses),Int32,(Ptr{Void},),w.handle)
        height(t::Terminal) = height(stdscr(t))
        size(t::NCursesSurface) = Size(width(t),height(t))

        # Panels library
        export Panel, make_visible, make_invisible, replace_window!

        type Panel
            handle::Ptr{Void}
            s::Window
            Panel(s::Window) = new(ccall((:new_panel,panel),Ptr{Void},(Ptr{Void},),s.handle),s)
            Panel(p::Ptr{Void},w::Window) = new(p,w)
        end

        function flush(t::Terminal)
            ccall((:update_panels,panel),Void,())
            ccall((:doupdate,panel),Void,()) 
        end

        function replace_window!(p::Panel,w::Window)
            ccall((:replace_panel,panel),Void,(Ptr{Void},Ptr{Void}),p.handle,w.handle)
            p.s = w
        end

        function make_visible(p::Panel)
            ccall((:show_panel,panel),Void,(Ptr{Void},),p.handle)
        end

        function make_invisible(p::Panel)
            ccall((:hide_panel,panel),Void,(Ptr{Void},),p.handle)
        end

        function move(p::Panel,x,y)
            ccall((:move_panel,panel),Void,(Ptr{Void},Int32,Int32),x,y)
        end
    end

    module Unix
        importall Terminals

        import Terminals: width, height, cmove, Rect, Size, getX, 
                          getY, raw!, clear_line, beep
        import Base: size, read, write, flush, TTY

        type UnixTerminal <: TextTerminal
            term_type
            in_stream::TTY
            out_stream::TTY
            err_stream::TTY
        end

        const CSI = "\x1b["

        cmove_up(t::UnixTerminal,n) = write(t.in_stream,"$(CSI)$(n)A")
        cmove_down(t::UnixTerminal,n) = write(t.in_stream,"$(CSI)$(n)B")
        cmove_right(t::UnixTerminal,n) = write(t.in_stream,"$(CSI)$(n)C")
        cmove_left(t::UnixTerminal,n) = write(t.in_stream,"$(CSI)$(n)D")
        cmove_line_up(t::UnixTerminal,n) = (cmove_up(t,n);cmove_col(t,0))
        cmove_line_down(t::UnixTerminal,n) = (cmove_down(t,n);cmove_col(t,0))
        cmove_col(t::UnixTerminal,n) = write(t.in_stream,"$(CSI)$(n)G")

        raw!(t::UnixTerminal,raw::Bool) = uv_error("raw!",ccall(:uv_tty_set_mode,Int32,(Ptr{Void},Int32),t.in_stream.handle,raw?1:0)==-1)

        function size(t::UnixTerminal)
            s = Array(Int32,2)
            uv_error("size (TTY)",ccall(:uv_tty_get_winsize,Int32,(Ptr{Void},Ptr{Int32},Ptr{Int32}),t.out_stream.handle,pointer(s,1),pointer(s,2))!=0)
            Size(s[1],s[2])
        end

        clear(t::UnixTerminal) = write(t.in_stream,"\x1b[H\x1b[2J")
        clear_line(t::UnixTerminal) = write(t.in_stream,"\x1b[0G\x1b[0K")
        beep(t::UnixTerminal) = write(t.err_stream,"\x7")

        write(t::UnixTerminal,args...) = write(t.out_stream,args...)
        read(t::UnixTerminal,args...) = read(t.in_stream,args...)
    end
end