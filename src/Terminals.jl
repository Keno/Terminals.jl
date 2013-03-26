module Terminals
    import Base.size, Base.write, Base.flush
    abstract TextTerminal <: Base.IO
    export TextTerminal, NCurses, writepos, move, pos, getX, getY

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
    move(t::TextTerminal,x,y) = error("Unimplemented")
    getX(t::TextTerminal) = error("Unimplemented")
    getY(t::TextTerminal) = error("Unimplemented")
    pos(t::TextTerminal) = (getX(t),getY(t))

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
            move(t,x,y)
            invoke(write, (IO, Array), s, a)
        end
    end
    function writepos(t::TextTerminal,x,y,args...)
        move(t,x,y)
        write(t,args...)
    end 
    width(t::TextTerminal) = size(t).width
    height(t::TextTerminal) = size(t).height

    # For terminals with buffers
    flush(t::TextTerminal) = nothing

    # Unix Terminals
    module NCurses
        importall Terminals
        import Terminals.width, Terminals.height, Terminals.move, Terminals.Rect, Terminals.Size
        import Base.size, Base.write, Base.flush

        abstract NCursesSurface <: TextTerminal


        # Libraries
        const ncurses = :libncurses

        type Terminal <: NCursesSurface
            auto_flush::Bool

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
                new(auto_flush)
            end
            Terminal() = Terminal(true,false)

        end

        flush(t::Terminal) = ccall((:refresh,ncurses),Void,())

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
            Window(auto_flush::Bool,dim::Rect) = new(auto_flush,ccall((:newwin,ncurses),Ptr{Void},(Int32,Int32,Int32,Int32),dim.height,dim.width,dim.top,dim.left))
            Window(auto_flush,height,width,left,top) = Window(auto_flush,Rect(top,left,width,height))
            Window(dim::Rect) = Window(true,dim)
            Window(height,width,left,top) = Window(true,height,width,left,top)
        end

        flush(w::Window) = ccall((:wrefresh,ncurses),Void,(Ptr{Void},),w.handle)

        macro writefunc(t,expr)
            quote
                $(esc(expr))
                if ($(esc(t)).auto_flush)
                    flush($(esc(t)))
                end
            end
        end

        # Ideally this would use a ccall-like API. Do we have that?
        const stdscr_symb = dlsym(dlopen("libncurses"),:stdscr)
        stdscr(::Terminal) = Window(unsafe_ref(convert(Ptr{Ptr{Void}},stdscr_symb)))

        # write
        write(t::Terminal, c::Uint8) = @writefunc t ccall((:addch,ncurses),Int32,(curses_chtype,),c)
        write(w::Window, c::Uint8) = @writefunc w ccall((:waddch,ncurses),Int32,(Ptr{Void},curses_chtype),w.handle,c)
        write(t::Terminal, b::Array{Uint8,1}) = @writefunc t ccall((:addnstr,ncurses),Int32,(Ptr{Uint8},Int32),b,length(b))
        write(w::Window, b::Array{Uint8,1}) = @writefunc w ccall((:waddnstr,ncurses),Int32,(Ptr{Void},Ptr{Uint8},Int32),w.handle,b,length(b))

        # writepos
        writepos(t::Terminal, x, y, c::Uint8) = @writefunc t ccall((:addch,ncurses),Int32,(Int32,Int32,curses_chtype,),x,y,c)
        writepos(w::Window, x, y, c::Uint8) = @writefunc w ccall((:waddch,ncurses),Int32,(Ptr{Void},Int32,Int32,curses_chtype),w.handle,x,y,c)
        writepos(t::Terminal, x, y, b::Array{Uint8,1}) = @writefunc t ccall((:mvaddnstr,ncurses),Int32,(Int32,Int32,Ptr{Uint8},Int32),x,yb,length(b))
        writepos(w::Window, x, y, b::Array{Uint8,1}) = @writefunc w ccall((:waddstr,ncurses),Int32,(Int32,Int32,Ptr{Void},Ptr{Uint8},Int32),w.handle,x,y,b,length(b))

        # move
        move(t::Terminal, x, y) = ccall((:move,ncurses),Void,(Int32,Int32),x,y)
        move(w::Window, x, y) = ccall((:wmove,ncurses),Void,(Ptr{Void},Int32,Int32),w.handle,x,y)

        # box
        box!(w::Window) = ccall((:box,ncurses),Int32,(Ptr{Void},curses_chtype,curses_chtype),w.handle,uint8('|'),uint8('-'))


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

    end
end