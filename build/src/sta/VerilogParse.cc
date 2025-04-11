// A Bison parser, made by GNU Bison 3.8.2.

// Skeleton implementation for Bison LALR(1) parsers in C++

// Copyright (C) 2002-2015, 2018-2021 Free Software Foundation, Inc.

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// As a special exception, you may create a larger work that contains
// part or all of the Bison parser skeleton and distribute that work
// under terms of your choice, so long as that work isn't itself a
// parser generator using the skeleton or a modified version thereof
// as a parser skeleton.  Alternatively, if you modify or redistribute
// the parser skeleton itself, you may (at your option) remove this
// special exception, which will cause the skeleton and the resulting
// Bison output files to be licensed under the GNU General Public
// License without this special exception.

// This special exception was added by the Free Software Foundation in
// version 2.2 of Bison.

// DO NOT RELY ON FEATURES THAT ARE NOT DOCUMENTED in the manual,
// especially those whose name start with YY_ or yy_.  They are
// private implementation details that can be changed or removed.



// First part of user prologue.
#line 25 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"

#include <cstdlib>
#include <string>

#include "Report.hh"
#include "PortDirection.hh"
#include "VerilogReader.hh"
#include "verilog/VerilogReaderPvt.hh"
#include "verilog/VerilogScanner.hh"

#undef yylex
#define yylex scanner->lex

// warning: variable 'yynerrs_' set but not used
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"

#define loc_line(loc) loc.begin.line

void
sta::VerilogParse::error(const location_type &loc,
                         const string &msg)
{
  reader->report()->fileError(164,reader->filename(),loc.begin.line,
                              "%s",msg.c_str());
}

#line 68 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"


#include "VerilogParse.hh"




#ifndef YY_
# if defined YYENABLE_NLS && YYENABLE_NLS
#  if ENABLE_NLS
#   include <libintl.h> // FIXME: INFRINGES ON USER NAME SPACE.
#   define YY_(msgid) dgettext ("bison-runtime", msgid)
#  endif
# endif
# ifndef YY_
#  define YY_(msgid) msgid
# endif
#endif


// Whether we are compiled with exception support.
#ifndef YY_EXCEPTIONS
# if defined __GNUC__ && !defined __EXCEPTIONS
#  define YY_EXCEPTIONS 0
# else
#  define YY_EXCEPTIONS 1
# endif
#endif

#define YYRHSLOC(Rhs, K) ((Rhs)[K].location)
/* YYLLOC_DEFAULT -- Set CURRENT to span from RHS[1] to RHS[N].
   If N is 0, then set CURRENT to the empty location which ends
   the previous symbol: RHS[0] (always defined).  */

# ifndef YYLLOC_DEFAULT
#  define YYLLOC_DEFAULT(Current, Rhs, N)                               \
    do                                                                  \
      if (N)                                                            \
        {                                                               \
          (Current).begin  = YYRHSLOC (Rhs, 1).begin;                   \
          (Current).end    = YYRHSLOC (Rhs, N).end;                     \
        }                                                               \
      else                                                              \
        {                                                               \
          (Current).begin = (Current).end = YYRHSLOC (Rhs, 0).end;      \
        }                                                               \
    while (false)
# endif


// Enable debugging if requested.
#if YYDEBUG

// A pseudo ostream that takes yydebug_ into account.
# define YYCDEBUG if (yydebug_) (*yycdebug_)

# define YY_SYMBOL_PRINT(Title, Symbol)         \
  do {                                          \
    if (yydebug_)                               \
    {                                           \
      *yycdebug_ << Title << ' ';               \
      yy_print_ (*yycdebug_, Symbol);           \
      *yycdebug_ << '\n';                       \
    }                                           \
  } while (false)

# define YY_REDUCE_PRINT(Rule)          \
  do {                                  \
    if (yydebug_)                       \
      yy_reduce_print_ (Rule);          \
  } while (false)

# define YY_STACK_PRINT()               \
  do {                                  \
    if (yydebug_)                       \
      yy_stack_print_ ();                \
  } while (false)

#else // !YYDEBUG

# define YYCDEBUG if (false) std::cerr
# define YY_SYMBOL_PRINT(Title, Symbol)  YY_USE (Symbol)
# define YY_REDUCE_PRINT(Rule)           static_cast<void> (0)
# define YY_STACK_PRINT()                static_cast<void> (0)

#endif // !YYDEBUG

#define yyerrok         (yyerrstatus_ = 0)
#define yyclearin       (yyla.clear ())

#define YYACCEPT        goto yyacceptlab
#define YYABORT         goto yyabortlab
#define YYERROR         goto yyerrorlab
#define YYRECOVERING()  (!!yyerrstatus_)

#line 55 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
namespace sta {
#line 166 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"

  /// Build a parser object.
  VerilogParse::VerilogParse (VerilogScanner *scanner_yyarg, VerilogReader *reader_yyarg)
#if YYDEBUG
    : yydebug_ (false),
      yycdebug_ (&std::cerr),
#else
    :
#endif
      scanner (scanner_yyarg),
      reader (reader_yyarg)
  {}

  VerilogParse::~VerilogParse ()
  {}

  VerilogParse::syntax_error::~syntax_error () YY_NOEXCEPT YY_NOTHROW
  {}

  /*---------.
  | symbol.  |
  `---------*/

  // basic_symbol.
  template <typename Base>
  VerilogParse::basic_symbol<Base>::basic_symbol (const basic_symbol& that)
    : Base (that)
    , value (that.value)
    , location (that.location)
  {}


  /// Constructor for valueless symbols.
  template <typename Base>
  VerilogParse::basic_symbol<Base>::basic_symbol (typename Base::kind_type t, YY_MOVE_REF (location_type) l)
    : Base (t)
    , value ()
    , location (l)
  {}

  template <typename Base>
  VerilogParse::basic_symbol<Base>::basic_symbol (typename Base::kind_type t, YY_RVREF (value_type) v, YY_RVREF (location_type) l)
    : Base (t)
    , value (YY_MOVE (v))
    , location (YY_MOVE (l))
  {}


  template <typename Base>
  VerilogParse::symbol_kind_type
  VerilogParse::basic_symbol<Base>::type_get () const YY_NOEXCEPT
  {
    return this->kind ();
  }


  template <typename Base>
  bool
  VerilogParse::basic_symbol<Base>::empty () const YY_NOEXCEPT
  {
    return this->kind () == symbol_kind::S_YYEMPTY;
  }

  template <typename Base>
  void
  VerilogParse::basic_symbol<Base>::move (basic_symbol& s)
  {
    super_type::move (s);
    value = YY_MOVE (s.value);
    location = YY_MOVE (s.location);
  }

  // by_kind.
  VerilogParse::by_kind::by_kind () YY_NOEXCEPT
    : kind_ (symbol_kind::S_YYEMPTY)
  {}

#if 201103L <= YY_CPLUSPLUS
  VerilogParse::by_kind::by_kind (by_kind&& that) YY_NOEXCEPT
    : kind_ (that.kind_)
  {
    that.clear ();
  }
#endif

  VerilogParse::by_kind::by_kind (const by_kind& that) YY_NOEXCEPT
    : kind_ (that.kind_)
  {}

  VerilogParse::by_kind::by_kind (token_kind_type t) YY_NOEXCEPT
    : kind_ (yytranslate_ (t))
  {}



  void
  VerilogParse::by_kind::clear () YY_NOEXCEPT
  {
    kind_ = symbol_kind::S_YYEMPTY;
  }

  void
  VerilogParse::by_kind::move (by_kind& that)
  {
    kind_ = that.kind_;
    that.clear ();
  }

  VerilogParse::symbol_kind_type
  VerilogParse::by_kind::kind () const YY_NOEXCEPT
  {
    return kind_;
  }


  VerilogParse::symbol_kind_type
  VerilogParse::by_kind::type_get () const YY_NOEXCEPT
  {
    return this->kind ();
  }



  // by_state.
  VerilogParse::by_state::by_state () YY_NOEXCEPT
    : state (empty_state)
  {}

  VerilogParse::by_state::by_state (const by_state& that) YY_NOEXCEPT
    : state (that.state)
  {}

  void
  VerilogParse::by_state::clear () YY_NOEXCEPT
  {
    state = empty_state;
  }

  void
  VerilogParse::by_state::move (by_state& that)
  {
    state = that.state;
    that.clear ();
  }

  VerilogParse::by_state::by_state (state_type s) YY_NOEXCEPT
    : state (s)
  {}

  VerilogParse::symbol_kind_type
  VerilogParse::by_state::kind () const YY_NOEXCEPT
  {
    if (state == empty_state)
      return symbol_kind::S_YYEMPTY;
    else
      return YY_CAST (symbol_kind_type, yystos_[+state]);
  }

  VerilogParse::stack_symbol_type::stack_symbol_type ()
  {}

  VerilogParse::stack_symbol_type::stack_symbol_type (YY_RVREF (stack_symbol_type) that)
    : super_type (YY_MOVE (that.state), YY_MOVE (that.value), YY_MOVE (that.location))
  {
#if 201103L <= YY_CPLUSPLUS
    // that is emptied.
    that.state = empty_state;
#endif
  }

  VerilogParse::stack_symbol_type::stack_symbol_type (state_type s, YY_MOVE_REF (symbol_type) that)
    : super_type (s, YY_MOVE (that.value), YY_MOVE (that.location))
  {
    // that is emptied.
    that.kind_ = symbol_kind::S_YYEMPTY;
  }

#if YY_CPLUSPLUS < 201103L
  VerilogParse::stack_symbol_type&
  VerilogParse::stack_symbol_type::operator= (const stack_symbol_type& that)
  {
    state = that.state;
    value = that.value;
    location = that.location;
    return *this;
  }

  VerilogParse::stack_symbol_type&
  VerilogParse::stack_symbol_type::operator= (stack_symbol_type& that)
  {
    state = that.state;
    value = that.value;
    location = that.location;
    // that is emptied.
    that.state = empty_state;
    return *this;
  }
#endif

  template <typename Base>
  void
  VerilogParse::yy_destroy_ (const char* yymsg, basic_symbol<Base>& yysym) const
  {
    if (yymsg)
      YY_SYMBOL_PRINT (yymsg, yysym);

    // User destructor.
    switch (yysym.kind ())
    {
      case symbol_kind::S_CONSTANT: // CONSTANT
#line 117 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
                    { delete (yysym.value.string); }
#line 379 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
        break;

      case symbol_kind::S_STRING: // STRING
#line 116 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
                    { delete (yysym.value.string); }
#line 385 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
        break;

      case symbol_kind::S_attr_spec_value: // attr_spec_value
#line 118 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
                    { delete (yysym.value.string); }
#line 391 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
        break;

      default:
        break;
    }
  }

#if YYDEBUG
  template <typename Base>
  void
  VerilogParse::yy_print_ (std::ostream& yyo, const basic_symbol<Base>& yysym) const
  {
    std::ostream& yyoutput = yyo;
    YY_USE (yyoutput);
    if (yysym.empty ())
      yyo << "empty symbol";
    else
      {
        symbol_kind_type yykind = yysym.kind ();
        yyo << (yykind < YYNTOKENS ? "token" : "nterm")
            << ' ' << yysym.name () << " ("
            << yysym.location << ": ";
        YY_USE (yykind);
        yyo << ')';
      }
  }
#endif

  void
  VerilogParse::yypush_ (const char* m, YY_MOVE_REF (stack_symbol_type) sym)
  {
    if (m)
      YY_SYMBOL_PRINT (m, sym);
    yystack_.push (YY_MOVE (sym));
  }

  void
  VerilogParse::yypush_ (const char* m, state_type s, YY_MOVE_REF (symbol_type) sym)
  {
#if 201103L <= YY_CPLUSPLUS
    yypush_ (m, stack_symbol_type (s, std::move (sym)));
#else
    stack_symbol_type ss (s, sym);
    yypush_ (m, ss);
#endif
  }

  void
  VerilogParse::yypop_ (int n) YY_NOEXCEPT
  {
    yystack_.pop (n);
  }

#if YYDEBUG
  std::ostream&
  VerilogParse::debug_stream () const
  {
    return *yycdebug_;
  }

  void
  VerilogParse::set_debug_stream (std::ostream& o)
  {
    yycdebug_ = &o;
  }


  VerilogParse::debug_level_type
  VerilogParse::debug_level () const
  {
    return yydebug_;
  }

  void
  VerilogParse::set_debug_level (debug_level_type l)
  {
    yydebug_ = l;
  }
#endif // YYDEBUG

  VerilogParse::state_type
  VerilogParse::yy_lr_goto_state_ (state_type yystate, int yysym)
  {
    int yyr = yypgoto_[yysym - YYNTOKENS] + yystate;
    if (0 <= yyr && yyr <= yylast_ && yycheck_[yyr] == yystate)
      return yytable_[yyr];
    else
      return yydefgoto_[yysym - YYNTOKENS];
  }

  bool
  VerilogParse::yy_pact_value_is_default_ (int yyvalue) YY_NOEXCEPT
  {
    return yyvalue == yypact_ninf_;
  }

  bool
  VerilogParse::yy_table_value_is_error_ (int yyvalue) YY_NOEXCEPT
  {
    return yyvalue == yytable_ninf_;
  }

  int
  VerilogParse::operator() ()
  {
    return parse ();
  }

  int
  VerilogParse::parse ()
  {
    int yyn;
    /// Length of the RHS of the rule being reduced.
    int yylen = 0;

    // Error handling.
    int yynerrs_ = 0;
    int yyerrstatus_ = 0;

    /// The lookahead symbol.
    symbol_type yyla;

    /// The locations where the error started and ended.
    stack_symbol_type yyerror_range[3];

    /// The return value of parse ().
    int yyresult;

#if YY_EXCEPTIONS
    try
#endif // YY_EXCEPTIONS
      {
    YYCDEBUG << "Starting parse\n";


    /* Initialize the stack.  The initial state will be set in
       yynewstate, since the latter expects the semantical and the
       location values to have been already stored, initialize these
       stacks with a primary value.  */
    yystack_.clear ();
    yypush_ (YY_NULLPTR, 0, YY_MOVE (yyla));

  /*-----------------------------------------------.
  | yynewstate -- push a new symbol on the stack.  |
  `-----------------------------------------------*/
  yynewstate:
    YYCDEBUG << "Entering state " << int (yystack_[0].state) << '\n';
    YY_STACK_PRINT ();

    // Accept?
    if (yystack_[0].state == yyfinal_)
      YYACCEPT;

    goto yybackup;


  /*-----------.
  | yybackup.  |
  `-----------*/
  yybackup:
    // Try to take a decision without lookahead.
    yyn = yypact_[+yystack_[0].state];
    if (yy_pact_value_is_default_ (yyn))
      goto yydefault;

    // Read a lookahead token.
    if (yyla.empty ())
      {
        YYCDEBUG << "Reading a token\n";
#if YY_EXCEPTIONS
        try
#endif // YY_EXCEPTIONS
          {
            yyla.kind_ = yytranslate_ (yylex (&yyla.value, &yyla.location));
          }
#if YY_EXCEPTIONS
        catch (const syntax_error& yyexc)
          {
            YYCDEBUG << "Caught exception: " << yyexc.what() << '\n';
            error (yyexc);
            goto yyerrlab1;
          }
#endif // YY_EXCEPTIONS
      }
    YY_SYMBOL_PRINT ("Next token is", yyla);

    if (yyla.kind () == symbol_kind::S_YYerror)
    {
      // The scanner already issued an error message, process directly
      // to error recovery.  But do not keep the error token as
      // lookahead, it is too special and may lead us to an endless
      // loop in error recovery. */
      yyla.kind_ = symbol_kind::S_YYUNDEF;
      goto yyerrlab1;
    }

    /* If the proper action on seeing token YYLA.TYPE is to reduce or
       to detect an error, take that action.  */
    yyn += yyla.kind ();
    if (yyn < 0 || yylast_ < yyn || yycheck_[yyn] != yyla.kind ())
      {
        goto yydefault;
      }

    // Reduce or error.
    yyn = yytable_[yyn];
    if (yyn <= 0)
      {
        if (yy_table_value_is_error_ (yyn))
          goto yyerrlab;
        yyn = -yyn;
        goto yyreduce;
      }

    // Count tokens shifted since error; after three, turn off error status.
    if (yyerrstatus_)
      --yyerrstatus_;

    // Shift the lookahead token.
    yypush_ ("Shifting", state_type (yyn), YY_MOVE (yyla));
    goto yynewstate;


  /*-----------------------------------------------------------.
  | yydefault -- do the default action for the current state.  |
  `-----------------------------------------------------------*/
  yydefault:
    yyn = yydefact_[+yystack_[0].state];
    if (yyn == 0)
      goto yyerrlab;
    goto yyreduce;


  /*-----------------------------.
  | yyreduce -- do a reduction.  |
  `-----------------------------*/
  yyreduce:
    yylen = yyr2_[yyn];
    {
      stack_symbol_type yylhs;
      yylhs.state = yy_lr_goto_state_ (yystack_[yylen].state, yyr1_[yyn]);
      /* If YYLEN is nonzero, implement the default value of the
         action: '$$ = $1'.  Otherwise, use the top of the stack.

         Otherwise, the following line sets YYLHS.VALUE to garbage.
         This behavior is undocumented and Bison users should not rely
         upon it.  */
      if (yylen)
        yylhs.value = yystack_[yylen - 1].value;
      else
        yylhs.value = yystack_[0].value;

      // Default location.
      {
        stack_type::slice range (yystack_, yylen);
        YYLLOC_DEFAULT (yylhs.location, range, yylen);
        yyerror_range[1].location = yylhs.location;
      }

      // Perform the reduction.
      YY_REDUCE_PRINT (yyn);
#if YY_EXCEPTIONS
      try
#endif // YY_EXCEPTIONS
        {
          switch (yyn)
            {
  case 5: // module: attr_instance_seq MODULE ID ';' stmts ENDMODULE
#line 135 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { reader->makeModule((yystack_[3].value.string), new sta::VerilogNetSeq,(yystack_[1].value.stmt_seq), (yystack_[5].value.attr_stmt_seq), loc_line(yystack_[4].location));}
#line 662 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 6: // module: attr_instance_seq MODULE ID '(' ')' ';' stmts ENDMODULE
#line 137 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { reader->makeModule((yystack_[5].value.string), new sta::VerilogNetSeq,(yystack_[1].value.stmt_seq), (yystack_[7].value.attr_stmt_seq), loc_line(yystack_[6].location));}
#line 668 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 7: // module: attr_instance_seq MODULE ID '(' port_list ')' ';' stmts ENDMODULE
#line 139 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { reader->makeModule((yystack_[6].value.string), (yystack_[4].value.nets), (yystack_[1].value.stmt_seq), (yystack_[8].value.attr_stmt_seq), loc_line(yystack_[7].location)); }
#line 674 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 8: // module: attr_instance_seq MODULE ID '(' port_dcls ')' ';' stmts ENDMODULE
#line 141 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { reader->makeModule((yystack_[6].value.string), (yystack_[4].value.stmt_seq), (yystack_[1].value.stmt_seq), (yystack_[8].value.attr_stmt_seq), loc_line(yystack_[7].location)); }
#line 680 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 9: // port_list: port
#line 146 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.nets) = new sta::VerilogNetSeq;
	  (yylhs.value.nets)->push_back((yystack_[0].value.net));
	}
#line 688 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 10: // port_list: port_list ',' port
#line 150 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yystack_[2].value.nets)->push_back((yystack_[0].value.net)); }
#line 694 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 11: // port: port_expr
#line 154 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 700 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 12: // port: '.' ID '(' ')'
#line 156 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetNamedPortRefScalar((yystack_[2].value.string), nullptr);}
#line 706 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 13: // port: '.' ID '(' port_expr ')'
#line 158 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetNamedPortRefScalar((yystack_[3].value.string), (yystack_[1].value.net));}
#line 712 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 14: // port_expr: port_ref
#line 162 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 718 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 15: // port_expr: '{' port_refs '}'
#line 164 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetConcat((yystack_[1].value.nets)); }
#line 724 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 16: // port_refs: port_ref
#line 168 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.nets) = new sta::VerilogNetSeq;
	  (yylhs.value.nets)->push_back((yystack_[0].value.net));
	}
#line 732 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 17: // port_refs: port_refs ',' port_ref
#line 172 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yystack_[2].value.nets)->push_back((yystack_[0].value.net)); }
#line 738 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 18: // port_ref: net_scalar
#line 176 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 744 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 19: // port_ref: net_bit_select
#line 177 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 750 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 20: // port_ref: net_part_select
#line 178 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 756 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 21: // port_dcls: port_dcl
#line 183 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt_seq) = new sta::VerilogStmtSeq;
	  (yylhs.value.stmt_seq)->push_back((yystack_[0].value.stmt));
	}
#line 764 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 22: // port_dcls: port_dcls ',' port_dcl
#line 187 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt_seq) = (yystack_[2].value.stmt_seq);
	  (yystack_[2].value.stmt_seq)->push_back((yystack_[0].value.stmt));
	}
#line 772 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 23: // port_dcls: port_dcls ',' dcl_arg
#line 191 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        {
	  sta::VerilogDcl *dcl = dynamic_cast<sta::VerilogDcl*>((yystack_[2].value.stmt_seq)->back());
	  dcl->appendArg((yystack_[0].value.dcl_arg));
	  (yylhs.value.stmt_seq) = (yystack_[2].value.stmt_seq);
	}
#line 782 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 24: // port_dcl: attr_instance_seq port_dcl_type dcl_arg
#line 200 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = reader->makeDcl((yystack_[1].value.port_type), (yystack_[0].value.dcl_arg), (yystack_[2].value.attr_stmt_seq), loc_line(yystack_[1].location)); }
#line 788 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 25: // port_dcl: attr_instance_seq port_dcl_type '[' INT ':' INT ']' dcl_arg
#line 202 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = reader->makeDclBus((yystack_[6].value.port_type), (yystack_[4].value.ival), (yystack_[2].value.ival), (yystack_[0].value.dcl_arg), (yystack_[7].value.attr_stmt_seq), loc_line(yystack_[6].location)); }
#line 794 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 26: // port_dcl_type: INPUT
#line 206 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
              { (yylhs.value.port_type) = sta::PortDirection::input(); }
#line 800 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 27: // port_dcl_type: INPUT WIRE
#line 207 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
                   { (yylhs.value.port_type) = sta::PortDirection::input(); }
#line 806 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 28: // port_dcl_type: INOUT
#line 208 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
              { (yylhs.value.port_type) = sta::PortDirection::bidirect(); }
#line 812 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 29: // port_dcl_type: INOUT REG
#line 209 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
                  { (yylhs.value.port_type) = sta::PortDirection::bidirect(); }
#line 818 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 30: // port_dcl_type: INOUT WIRE
#line 210 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
                   { (yylhs.value.port_type) = sta::PortDirection::bidirect(); }
#line 824 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 31: // port_dcl_type: OUTPUT
#line 211 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
               { (yylhs.value.port_type) = sta::PortDirection::output(); }
#line 830 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 32: // port_dcl_type: OUTPUT WIRE
#line 212 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
                    { (yylhs.value.port_type) = sta::PortDirection::output(); }
#line 836 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 33: // port_dcl_type: OUTPUT REG
#line 213 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
                   { (yylhs.value.port_type) = sta::PortDirection::output(); }
#line 842 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 34: // stmts: %empty
#line 218 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt_seq) = new sta::VerilogStmtSeq; }
#line 848 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 35: // stmts: stmts stmt
#line 220 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { if ((yystack_[0].value.stmt)) (yystack_[1].value.stmt_seq)->push_back((yystack_[0].value.stmt)); }
#line 854 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 36: // stmts: stmts stmt_seq
#line 223 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { sta::VerilogStmtSeq::Iterator iter((yystack_[0].value.stmt_seq));
	  while (iter.hasNext())
	    (yystack_[1].value.stmt_seq)->push_back(iter.next());
	  delete (yystack_[0].value.stmt_seq);
	}
#line 864 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 37: // stmt: parameter
#line 231 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = (yystack_[0].value.stmt); }
#line 870 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 38: // stmt: defparam
#line 232 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = (yystack_[0].value.stmt); }
#line 876 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 39: // stmt: declaration
#line 233 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = (yystack_[0].value.stmt); }
#line 882 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 40: // stmt: instance
#line 234 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = (yystack_[0].value.stmt); }
#line 888 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 41: // stmt: error ';'
#line 236 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { yyerrok; (yylhs.value.stmt) = nullptr; }
#line 894 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 42: // stmt_seq: continuous_assign
#line 240 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt_seq) = (yystack_[0].value.stmt_seq); }
#line 900 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 43: // parameter: PARAMETER parameter_dcls ';'
#line 246 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = nullptr; }
#line 906 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 44: // parameter: PARAMETER '[' INT ':' INT ']' parameter_dcls ';'
#line 248 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = nullptr; }
#line 912 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 45: // parameter_dcls: parameter_dcl
#line 253 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = nullptr; }
#line 918 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 46: // parameter_dcls: parameter_dcls ',' parameter_dcl
#line 255 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = nullptr; }
#line 924 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 47: // parameter_dcl: ID '=' parameter_expr
#line 260 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { delete (yystack_[2].value.string); (yylhs.value.stmt) = nullptr; }
#line 930 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 48: // parameter_dcl: ID '=' STRING
#line 262 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { delete (yystack_[2].value.string); delete (yystack_[0].value.string); (yylhs.value.stmt) = nullptr; }
#line 936 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 49: // parameter_expr: ID
#line 267 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { delete (yystack_[0].value.string); (yylhs.value.ival) = 0; }
#line 942 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 50: // parameter_expr: '`' ID
#line 269 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { delete (yystack_[0].value.string); (yylhs.value.ival) = 0; }
#line 948 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 51: // parameter_expr: CONSTANT
#line 271 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { delete (yystack_[0].value.string); (yylhs.value.ival) = 0; }
#line 954 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 52: // parameter_expr: INT
#line 272 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.ival) = (yystack_[0].value.ival); }
#line 960 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 53: // parameter_expr: '-' parameter_expr
#line 274 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.ival) = - (yystack_[0].value.ival); }
#line 966 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 54: // parameter_expr: parameter_expr '+' parameter_expr
#line 276 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.ival) = (yystack_[2].value.ival) + (yystack_[0].value.ival); }
#line 972 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 55: // parameter_expr: parameter_expr '-' parameter_expr
#line 278 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.ival) = (yystack_[2].value.ival) - (yystack_[0].value.ival); }
#line 978 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 56: // parameter_expr: parameter_expr '*' parameter_expr
#line 280 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.ival) = (yystack_[2].value.ival) * (yystack_[0].value.ival); }
#line 984 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 57: // parameter_expr: parameter_expr '/' parameter_expr
#line 282 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.ival) = (yystack_[2].value.ival) / (yystack_[0].value.ival); }
#line 990 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 58: // parameter_expr: '(' parameter_expr ')'
#line 284 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.ival) = (yystack_[1].value.ival); }
#line 996 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 59: // defparam: DEFPARAM param_values ';'
#line 289 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = nullptr; }
#line 1002 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 60: // param_values: param_value
#line 294 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = nullptr; }
#line 1008 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 61: // param_values: param_values ',' param_value
#line 296 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = nullptr; }
#line 1014 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 62: // param_value: ID '=' parameter_expr
#line 301 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { delete (yystack_[2].value.string); (yylhs.value.stmt) = nullptr; }
#line 1020 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 63: // param_value: ID '=' STRING
#line 303 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { delete (yystack_[2].value.string); delete (yystack_[0].value.string); (yylhs.value.stmt) = nullptr; }
#line 1026 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 64: // declaration: attr_instance_seq dcl_type dcl_args ';'
#line 308 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = reader->makeDcl((yystack_[2].value.port_type), (yystack_[1].value.dcl_arg_seq), (yystack_[3].value.attr_stmt_seq), loc_line(yystack_[2].location)); }
#line 1032 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 65: // declaration: attr_instance_seq dcl_type '[' INT ':' INT ']' dcl_args ';'
#line 310 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = reader->makeDclBus((yystack_[7].value.port_type), (yystack_[5].value.ival), (yystack_[3].value.ival), (yystack_[1].value.dcl_arg_seq), (yystack_[8].value.attr_stmt_seq),loc_line(yystack_[7].location)); }
#line 1038 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 66: // dcl_type: INPUT
#line 314 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
              { (yylhs.value.port_type) = sta::PortDirection::input(); }
#line 1044 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 67: // dcl_type: INOUT
#line 315 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
              { (yylhs.value.port_type) = sta::PortDirection::bidirect(); }
#line 1050 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 68: // dcl_type: OUTPUT
#line 316 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
               { (yylhs.value.port_type) = sta::PortDirection::output(); }
#line 1056 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 69: // dcl_type: SUPPLY0
#line 317 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
                { (yylhs.value.port_type) = sta::PortDirection::ground(); }
#line 1062 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 70: // dcl_type: SUPPLY1
#line 318 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
                { (yylhs.value.port_type) = sta::PortDirection::power(); }
#line 1068 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 71: // dcl_type: TRI
#line 319 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
            { (yylhs.value.port_type) = sta::PortDirection::tristate(); }
#line 1074 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 72: // dcl_type: WAND
#line 320 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
             { (yylhs.value.port_type) = sta::PortDirection::internal(); }
#line 1080 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 73: // dcl_type: WIRE
#line 321 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
             { (yylhs.value.port_type) = sta::PortDirection::internal(); }
#line 1086 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 74: // dcl_type: WOR
#line 322 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
            { (yylhs.value.port_type) = sta::PortDirection::internal(); }
#line 1092 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 75: // dcl_args: dcl_arg
#line 327 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.dcl_arg_seq) = new sta::VerilogDclArgSeq;
	  (yylhs.value.dcl_arg_seq)->push_back((yystack_[0].value.dcl_arg));
	}
#line 1100 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 76: // dcl_args: dcl_args ',' dcl_arg
#line 331 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yystack_[2].value.dcl_arg_seq)->push_back((yystack_[0].value.dcl_arg));
	  (yylhs.value.dcl_arg_seq) = (yystack_[2].value.dcl_arg_seq);
	}
#line 1108 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 77: // dcl_arg: ID
#line 338 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.dcl_arg) = reader->makeDclArg((yystack_[0].value.string)); }
#line 1114 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 78: // dcl_arg: net_assignment
#line 340 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.dcl_arg) = reader->makeDclArg((yystack_[0].value.assign)); }
#line 1120 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 79: // continuous_assign: ASSIGN net_assignments ';'
#line 345 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt_seq) = (yystack_[1].value.stmt_seq); }
#line 1126 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 80: // net_assignments: net_assignment
#line 350 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt_seq) = new sta::VerilogStmtSeq();
	  (yylhs.value.stmt_seq)->push_back((yystack_[0].value.assign));
	}
#line 1134 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 81: // net_assignments: net_assignments ',' net_assignment
#line 354 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yystack_[2].value.stmt_seq)->push_back((yystack_[0].value.assign)); }
#line 1140 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 82: // net_assignment: net_assign_lhs '=' net_expr
#line 359 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.assign) = reader->makeAssign((yystack_[2].value.net), (yystack_[0].value.net), loc_line(yystack_[2].location)); }
#line 1146 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 83: // net_assign_lhs: net_named
#line 363 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1152 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 84: // net_assign_lhs: net_expr_concat
#line 364 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
          { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1158 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 85: // instance: attr_instance_seq ID ID '(' inst_pins ')' ';'
#line 369 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = reader->makeModuleInst((yystack_[5].value.string), (yystack_[4].value.string), (yystack_[2].value.nets), (yystack_[6].value.attr_stmt_seq), loc_line(yystack_[5].location)); }
#line 1164 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 86: // instance: attr_instance_seq ID parameter_values ID '(' inst_pins ')' ';'
#line 371 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.stmt) = reader->makeModuleInst((yystack_[6].value.string), (yystack_[4].value.string), (yystack_[2].value.nets), (yystack_[7].value.attr_stmt_seq), loc_line(yystack_[6].location)); }
#line 1170 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 88: // parameter_exprs: parameter_expr
#line 379 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.ival) = (yystack_[0].value.ival); }
#line 1176 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 89: // parameter_exprs: '{' parameter_exprs '}'
#line 381 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.ival) = (yystack_[1].value.ival); }
#line 1182 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 90: // parameter_exprs: parameter_exprs ',' parameter_expr
#line 382 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.ival) = (yystack_[2].value.ival); }
#line 1188 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 91: // inst_pins: %empty
#line 387 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.nets) = nullptr; }
#line 1194 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 92: // inst_pins: inst_ordered_pins
#line 388 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.nets) = (yystack_[0].value.nets); }
#line 1200 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 93: // inst_pins: inst_named_pins
#line 389 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.nets) = (yystack_[0].value.nets); }
#line 1206 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 94: // inst_ordered_pins: net_expr
#line 395 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.nets) = new sta::VerilogNetSeq;
	  (yylhs.value.nets)->push_back((yystack_[0].value.net));
	}
#line 1214 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 95: // inst_ordered_pins: inst_ordered_pins ',' net_expr
#line 399 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yystack_[2].value.nets)->push_back((yystack_[0].value.net)); }
#line 1220 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 96: // inst_named_pins: inst_named_pin
#line 405 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.nets) = new sta::VerilogNetSeq;
	  (yylhs.value.nets)->push_back((yystack_[0].value.net));
	}
#line 1228 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 97: // inst_named_pins: inst_named_pins ',' inst_named_pin
#line 409 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yystack_[2].value.nets)->push_back((yystack_[0].value.net)); }
#line 1234 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 98: // inst_named_pin: '.' ID '(' ')'
#line 417 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetNamedPortRefScalarNet((yystack_[2].value.string)); }
#line 1240 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 99: // inst_named_pin: '.' ID '(' ID ')'
#line 419 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetNamedPortRefScalarNet((yystack_[3].value.string), (yystack_[1].value.string)); }
#line 1246 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 100: // inst_named_pin: '.' ID '(' ID '[' INT ']' ')'
#line 421 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetNamedPortRefBitSelect((yystack_[6].value.string), (yystack_[4].value.string), (yystack_[2].value.ival)); }
#line 1252 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 101: // inst_named_pin: '.' ID '(' named_pin_net_expr ')'
#line 423 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetNamedPortRefScalar((yystack_[3].value.string), (yystack_[1].value.net)); }
#line 1258 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 102: // inst_named_pin: '.' ID '[' INT ']' '(' ')'
#line 426 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetNamedPortRefBit((yystack_[5].value.string), (yystack_[3].value.ival), nullptr); }
#line 1264 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 103: // inst_named_pin: '.' ID '[' INT ']' '(' net_expr ')'
#line 428 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetNamedPortRefBit((yystack_[6].value.string), (yystack_[4].value.ival), (yystack_[1].value.net)); }
#line 1270 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 104: // inst_named_pin: '.' ID '[' INT ':' INT ']' '(' ')'
#line 431 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetNamedPortRefPart((yystack_[7].value.string), (yystack_[5].value.ival), (yystack_[3].value.ival), nullptr); }
#line 1276 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 105: // inst_named_pin: '.' ID '[' INT ':' INT ']' '(' net_expr ')'
#line 433 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetNamedPortRefPart((yystack_[8].value.string), (yystack_[6].value.ival), (yystack_[4].value.ival), (yystack_[1].value.net)); }
#line 1282 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 106: // named_pin_net_expr: net_part_select
#line 437 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1288 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 107: // named_pin_net_expr: net_constant
#line 438 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1294 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 108: // named_pin_net_expr: net_expr_concat
#line 439 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1300 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 109: // net_named: net_scalar
#line 443 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1306 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 110: // net_named: net_bit_select
#line 444 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1312 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 111: // net_named: net_part_select
#line 445 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1318 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 112: // net_scalar: ID
#line 450 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetScalar((yystack_[0].value.string)); }
#line 1324 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 113: // net_bit_select: ID '[' INT ']'
#line 455 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetBitSelect((yystack_[3].value.string), (yystack_[1].value.ival)); }
#line 1330 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 114: // net_part_select: ID '[' INT ':' INT ']'
#line 460 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetPartSelect((yystack_[5].value.string), (yystack_[3].value.ival), (yystack_[1].value.ival)); }
#line 1336 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 115: // net_constant: CONSTANT
#line 465 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetConstant((yystack_[0].value.string), loc_line(yystack_[0].location)); }
#line 1342 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 116: // net_expr_concat: '{' net_exprs '}'
#line 470 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = reader->makeNetConcat((yystack_[1].value.nets)); }
#line 1348 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 117: // net_exprs: net_expr
#line 475 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.nets) = new sta::VerilogNetSeq;
	  (yylhs.value.nets)->push_back((yystack_[0].value.net));
	}
#line 1356 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 118: // net_exprs: net_exprs ',' net_expr
#line 479 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.nets)->push_back((yystack_[0].value.net)); }
#line 1362 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 119: // net_expr: net_scalar
#line 483 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1368 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 120: // net_expr: net_bit_select
#line 484 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1374 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 121: // net_expr: net_part_select
#line 485 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1380 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 122: // net_expr: net_constant
#line 486 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1386 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 123: // net_expr: net_expr_concat
#line 487 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.net) = (yystack_[0].value.net); }
#line 1392 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 124: // attr_instance_seq: %empty
#line 492 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.attr_stmt_seq) = new sta::VerilogAttrStmtSeq; }
#line 1398 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 125: // attr_instance_seq: attr_instance_seq attr_instance
#line 494 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { if ((yystack_[0].value.attr_stmt)) (yystack_[1].value.attr_stmt_seq)->push_back((yystack_[0].value.attr_stmt)); }
#line 1404 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 126: // attr_instance: ATTR_OPEN attr_specs ATTR_CLOSED
#line 499 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.attr_stmt) = new sta::VerilogAttrStmt((yystack_[1].value.attr_seq)); }
#line 1410 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 127: // attr_specs: attr_spec
#line 504 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.attr_seq) = new sta::VerilogAttrEntrySeq;
	  (yylhs.value.attr_seq)->push_back((yystack_[0].value.attr_entry));
	}
#line 1418 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 128: // attr_specs: attr_specs ',' attr_spec
#line 508 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.attr_seq)->push_back((yystack_[0].value.attr_entry)); }
#line 1424 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 129: // attr_spec: ID
#line 513 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.attr_entry) = new sta::VerilogAttrEntry(*(yystack_[0].value.string), "1"); delete (yystack_[0].value.string); }
#line 1430 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 130: // attr_spec: ID '=' attr_spec_value
#line 515 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.attr_entry) = new sta::VerilogAttrEntry(*(yystack_[2].value.string), *(yystack_[0].value.string)); delete (yystack_[2].value.string); delete (yystack_[0].value.string); }
#line 1436 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 131: // attr_spec_value: CONSTANT
#line 520 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.string) = (yystack_[0].value.string); }
#line 1442 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 132: // attr_spec_value: STRING
#line 522 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.string) = (yystack_[0].value.string); }
#line 1448 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;

  case 133: // attr_spec_value: INT
#line 524 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
        { (yylhs.value.string) = new string(std::to_string((yystack_[0].value.ival))); }
#line 1454 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"
    break;


#line 1458 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"

            default:
              break;
            }
        }
#if YY_EXCEPTIONS
      catch (const syntax_error& yyexc)
        {
          YYCDEBUG << "Caught exception: " << yyexc.what() << '\n';
          error (yyexc);
          YYERROR;
        }
#endif // YY_EXCEPTIONS
      YY_SYMBOL_PRINT ("-> $$ =", yylhs);
      yypop_ (yylen);
      yylen = 0;

      // Shift the result of the reduction.
      yypush_ (YY_NULLPTR, YY_MOVE (yylhs));
    }
    goto yynewstate;


  /*--------------------------------------.
  | yyerrlab -- here on detecting error.  |
  `--------------------------------------*/
  yyerrlab:
    // If not already recovering from an error, report this error.
    if (!yyerrstatus_)
      {
        ++yynerrs_;
        std::string msg = YY_("syntax error");
        error (yyla.location, YY_MOVE (msg));
      }


    yyerror_range[1].location = yyla.location;
    if (yyerrstatus_ == 3)
      {
        /* If just tried and failed to reuse lookahead token after an
           error, discard it.  */

        // Return failure if at end of input.
        if (yyla.kind () == symbol_kind::S_YYEOF)
          YYABORT;
        else if (!yyla.empty ())
          {
            yy_destroy_ ("Error: discarding", yyla);
            yyla.clear ();
          }
      }

    // Else will try to reuse lookahead token after shifting the error token.
    goto yyerrlab1;


  /*---------------------------------------------------.
  | yyerrorlab -- error raised explicitly by YYERROR.  |
  `---------------------------------------------------*/
  yyerrorlab:
    /* Pacify compilers when the user code never invokes YYERROR and
       the label yyerrorlab therefore never appears in user code.  */
    if (false)
      YYERROR;

    /* Do not reclaim the symbols of the rule whose action triggered
       this YYERROR.  */
    yypop_ (yylen);
    yylen = 0;
    YY_STACK_PRINT ();
    goto yyerrlab1;


  /*-------------------------------------------------------------.
  | yyerrlab1 -- common code for both syntax error and YYERROR.  |
  `-------------------------------------------------------------*/
  yyerrlab1:
    yyerrstatus_ = 3;   // Each real token shifted decrements this.
    // Pop stack until we find a state that shifts the error token.
    for (;;)
      {
        yyn = yypact_[+yystack_[0].state];
        if (!yy_pact_value_is_default_ (yyn))
          {
            yyn += symbol_kind::S_YYerror;
            if (0 <= yyn && yyn <= yylast_
                && yycheck_[yyn] == symbol_kind::S_YYerror)
              {
                yyn = yytable_[yyn];
                if (0 < yyn)
                  break;
              }
          }

        // Pop the current state because it cannot handle the error token.
        if (yystack_.size () == 1)
          YYABORT;

        yyerror_range[1].location = yystack_[0].location;
        yy_destroy_ ("Error: popping", yystack_[0]);
        yypop_ ();
        YY_STACK_PRINT ();
      }
    {
      stack_symbol_type error_token;

      yyerror_range[2].location = yyla.location;
      YYLLOC_DEFAULT (error_token.location, yyerror_range, 2);

      // Shift the error token.
      error_token.state = state_type (yyn);
      yypush_ ("Shifting", YY_MOVE (error_token));
    }
    goto yynewstate;


  /*-------------------------------------.
  | yyacceptlab -- YYACCEPT comes here.  |
  `-------------------------------------*/
  yyacceptlab:
    yyresult = 0;
    goto yyreturn;


  /*-----------------------------------.
  | yyabortlab -- YYABORT comes here.  |
  `-----------------------------------*/
  yyabortlab:
    yyresult = 1;
    goto yyreturn;


  /*-----------------------------------------------------.
  | yyreturn -- parsing is finished, return the result.  |
  `-----------------------------------------------------*/
  yyreturn:
    if (!yyla.empty ())
      yy_destroy_ ("Cleanup: discarding lookahead", yyla);

    /* Do not reclaim the symbols of the rule whose action triggered
       this YYABORT or YYACCEPT.  */
    yypop_ (yylen);
    YY_STACK_PRINT ();
    while (1 < yystack_.size ())
      {
        yy_destroy_ ("Cleanup: popping", yystack_[0]);
        yypop_ ();
      }

    return yyresult;
  }
#if YY_EXCEPTIONS
    catch (...)
      {
        YYCDEBUG << "Exception caught: cleaning lookahead and stack\n";
        // Do not try to display the values of the reclaimed symbols,
        // as their printers might throw an exception.
        if (!yyla.empty ())
          yy_destroy_ (YY_NULLPTR, yyla);

        while (1 < yystack_.size ())
          {
            yy_destroy_ (YY_NULLPTR, yystack_[0]);
            yypop_ ();
          }
        throw;
      }
#endif // YY_EXCEPTIONS
  }

  void
  VerilogParse::error (const syntax_error& yyexc)
  {
    error (yyexc.location, yyexc.what ());
  }

#if YYDEBUG || 0
  const char *
  VerilogParse::symbol_name (symbol_kind_type yysymbol)
  {
    return yytname_[yysymbol];
  }
#endif // #if YYDEBUG || 0









  const signed char VerilogParse::yypact_ninf_ = -112;

  const signed char VerilogParse::yytable_ninf_ = -125;

  const short
  VerilogParse::yypact_[] =
  {
    -112,    24,    64,  -112,  -112,    10,   101,   105,  -112,   143,
     -17,    -2,  -112,  -112,   128,   214,  -112,   105,   194,    91,
     102,   120,   130,   165,  -112,  -112,  -112,   262,  -112,  -112,
    -112,  -112,   168,  -112,  -112,  -112,  -112,  -112,   119,  -112,
      87,     1,   147,  -112,  -112,  -112,  -112,  -112,  -112,  -112,
     286,   151,  -112,   135,    70,  -112,   150,    39,   152,    89,
     171,    17,    83,    22,  -112,    35,    90,  -112,   148,  -112,
    -112,  -112,  -112,  -112,   153,   198,   121,  -112,   176,   131,
    -112,    11,  -112,  -112,  -112,  -112,  -112,  -112,  -112,  -112,
    -112,    23,   258,   230,    15,   130,  -112,  -112,  -112,  -112,
     138,  -112,  -112,  -112,  -112,  -112,  -112,  -112,  -112,   220,
    -112,  -112,  -112,  -112,  -112,  -112,  -112,   187,  -112,  -112,
      87,    35,    30,   188,  -112,   222,    73,  -112,   147,   199,
     203,   232,   271,   192,  -112,   274,  -112,  -112,  -112,   266,
    -112,   250,   270,   281,    35,  -112,  -112,  -112,  -112,  -112,
    -112,  -112,    96,    96,   302,   115,   312,  -112,  -112,   115,
    -112,    57,    84,   289,   283,  -112,    89,   284,  -112,  -112,
    -112,   318,  -112,  -112,   144,  -112,    96,    96,    96,    96,
     287,   319,   292,   294,   295,  -112,  -112,    84,   115,   278,
      57,   325,  -112,  -112,   291,  -112,   285,   285,  -112,  -112,
     222,    -5,   301,    35,   298,   221,  -112,    96,   303,   297,
      89,   225,   112,   329,  -112,  -112,  -112,  -112,   115,   304,
      89,  -112,  -112,   -13,  -112,   305,  -112,  -112,  -112,   276,
    -112,   244,  -112,   334,  -112,   335,   309,  -112,   279,   306,
     124,   310,   313,  -112,   311,  -112,   133,  -112,  -112,   314,
    -112
  };

  const unsigned char
  VerilogParse::yydefact_[] =
  {
       3,     0,   124,     1,     4,     0,     0,     0,   125,     0,
     129,     0,   127,    34,   124,     0,   126,     0,     0,   112,
       0,     0,     0,     0,     9,    11,    14,     0,    21,    18,
      19,    20,     0,   133,   131,   132,   130,   128,     0,     5,
       0,     0,     0,    35,    36,    37,    38,    39,    42,    40,
       0,     0,    34,     0,     0,    16,     0,     0,     0,   124,
      26,    31,    28,     0,    41,     0,     0,    80,     0,    83,
     109,   110,   111,    84,     0,     0,     0,    45,     0,     0,
      60,     0,    73,    72,    74,    71,    66,    68,    67,    70,
      69,     0,     0,     0,     0,     0,    15,    34,    10,    34,
      77,    22,    23,    78,    27,    32,    33,    30,    29,     0,
      24,   115,   119,   120,   121,   122,   123,     0,   117,    79,
       0,     0,     0,     0,    43,     0,     0,    59,     0,     0,
       0,     0,     0,     0,    75,     0,   113,     6,    12,     0,
      17,     0,     0,     0,     0,   116,    81,    82,    52,    51,
      49,    48,     0,     0,     0,    47,     0,    46,    63,    62,
      61,    91,     0,     0,     0,    64,     0,     0,    13,     7,
       8,     0,   118,    53,     0,    50,     0,     0,     0,     0,
       0,     0,     0,    92,    93,    96,    94,     0,    88,     0,
      91,     0,    76,   114,     0,    58,    55,    54,    56,    57,
       0,     0,     0,     0,     0,     0,    87,     0,     0,     0,
       0,     0,     0,     0,    85,    95,    97,    89,    90,     0,
       0,    25,    44,     0,    98,     0,   106,   107,   108,     0,
      86,     0,    99,     0,   101,     0,     0,    65,     0,     0,
       0,     0,     0,   102,     0,   100,     0,   103,   104,     0,
     105
  };

  const short
  VerilogParse::yypgoto_[] =
  {
    -112,  -112,  -112,  -112,  -112,   290,   246,  -112,   -21,  -112,
     293,  -112,   -49,  -112,  -112,  -112,   146,   223,  -111,  -112,
    -112,   226,  -112,  -112,   129,   -54,  -112,  -112,   -27,  -112,
    -112,  -112,   163,   161,  -112,  -112,   149,  -112,  -112,   -12,
     -10,   -14,   145,   -46,  -112,   -58,    12,  -112,  -112,   338,
    -112
  };

  const unsigned char
  VerilogParse::yydefgoto_[] =
  {
       0,     1,     2,     4,    23,    24,    25,    54,    26,    27,
      28,    63,    18,    43,    44,    45,    76,    77,   188,    46,
      79,    80,    47,    91,   133,   134,    48,    66,   103,    68,
      49,   131,   189,   182,   183,   184,   185,   225,    69,    70,
      71,    72,   115,    73,   117,   186,    50,     8,    11,    12,
      36
  };

  const short
  VerilogParse::yytable_[] =
  {
      31,    55,    29,    93,    30,   102,    74,   118,    31,   110,
      29,   155,    30,    67,     5,   159,   129,     6,   232,   116,
      19,    16,    15,   233,     3,   212,    32,   100,   100,   105,
      17,   213,     7,   148,   149,   150,   151,    75,   106,   111,
      19,   173,   174,    31,    19,    29,   138,    30,   141,    22,
     142,   114,   130,   112,   152,   113,    65,    65,   109,   132,
     153,   111,    19,   147,    -2,   196,   197,   198,   199,    65,
     154,    32,    21,    22,   140,   116,   148,   149,   150,   158,
      31,    31,    29,    29,    30,    30,   172,   148,   149,   150,
     181,    65,    19,   146,   100,   107,   218,   152,   116,   148,
     149,   150,    95,   153,   108,    96,     9,   114,   152,   112,
      10,   113,   192,   154,   153,   116,   111,   223,   187,   119,
     152,    65,   120,    65,   154,    53,   153,    51,   111,    19,
     114,    52,   112,    19,   113,    19,   154,   111,    19,   176,
     177,   178,   179,   224,   116,   215,    65,   114,    64,   112,
     124,   113,    78,   125,    92,   243,   221,   116,    65,    20,
     127,    21,    22,   128,   248,    94,   228,    65,   176,   177,
     178,   179,    13,    14,    51,   195,   114,  -112,   112,    97,
     113,    99,   244,   104,    60,    61,    62,   121,   249,   114,
       7,   112,   122,   113,   116,    38,    56,    57,   226,  -124,
     116,   123,    39,    40,    41,    42,  -124,  -124,  -124,  -124,
    -124,  -124,  -124,  -124,  -124,   126,  -124,    33,    34,   144,
      35,   165,   145,   143,   166,   156,   114,    74,   112,   161,
     113,    38,   114,   162,   112,  -124,   113,   163,   137,    40,
      41,    42,  -124,  -124,  -124,  -124,  -124,  -124,  -124,  -124,
    -124,    38,  -124,   207,   222,  -124,   217,   125,   169,    40,
      41,    42,  -124,  -124,  -124,  -124,  -124,  -124,  -124,  -124,
    -124,    38,  -124,   237,   164,  -124,   166,   167,   170,    40,
      41,    42,  -124,  -124,  -124,  -124,  -124,  -124,  -124,  -124,
    -124,    81,  -124,    58,    59,   135,   136,   168,    82,    83,
      84,    85,    86,    87,    88,    89,    90,   175,     7,   206,
     207,   178,   179,   235,   236,   180,   135,   241,   171,   190,
     191,   194,   193,   202,   201,   200,   203,   204,   209,   210,
     214,   181,   229,   230,   219,   220,   234,   238,   239,   240,
     139,   245,   247,   246,   242,   250,   211,    98,   157,   231,
     205,   208,   101,   216,   160,    37,     0,   227
  };

  const short
  VerilogParse::yycheck_[] =
  {
      14,    22,    14,    52,    14,    59,     5,    65,    22,    63,
      22,   122,    22,    40,     2,   126,     5,     7,    31,    65,
       5,    23,    39,    36,     0,    30,    14,     5,     5,    12,
      32,    36,    22,     3,     4,     5,     6,    36,    21,     4,
       5,   152,   153,    57,     5,    57,    31,    57,    97,    34,
      99,    65,    41,    65,    24,    65,    34,    34,    36,    36,
      30,     4,     5,   121,     0,   176,   177,   178,   179,    34,
      40,    59,    33,    34,    95,   121,     3,     4,     5,     6,
      94,    95,    94,    95,    94,    95,   144,     3,     4,     5,
      33,    34,     5,   120,     5,    12,   207,    24,   144,     3,
       4,     5,    32,    30,    21,    35,     5,   121,    24,   121,
       5,   121,   166,    40,    30,   161,     4,     5,    34,    29,
      24,    34,    32,    34,    40,     5,    30,    36,     4,     5,
     144,    29,   144,     5,   144,     5,    40,     4,     5,    24,
      25,    26,    27,    31,   190,   203,    34,   161,    29,   161,
      29,   161,     5,    32,     3,    31,   210,   203,    34,    31,
      29,    33,    34,    32,    31,    30,   212,    34,    24,    25,
      26,    27,    29,    30,    36,    31,   190,    39,   190,    29,
     190,    29,   240,    12,    16,    17,    18,    39,   246,   203,
      22,   203,    39,   203,   240,     1,    31,    32,   212,     5,
     246,     3,     8,     9,    10,    11,    12,    13,    14,    15,
      16,    17,    18,    19,    20,    39,    22,     3,     4,    32,
       6,    29,    35,     3,    32,    37,   240,     5,   240,    30,
     240,     1,   246,    30,   246,     5,   246,     5,     8,     9,
      10,    11,    12,    13,    14,    15,    16,    17,    18,    19,
      20,     1,    22,    32,    29,     5,    35,    32,     8,     9,
      10,    11,    12,    13,    14,    15,    16,    17,    18,    19,
      20,     1,    22,    29,     3,     5,    32,     3,     8,     9,
      10,    11,    12,    13,    14,    15,    16,    17,    18,    19,
      20,     5,    22,    31,    32,    37,    38,    31,    12,    13,
      14,    15,    16,    17,    18,    19,    20,     5,    22,    31,
      32,    26,    27,    37,    38,     3,    37,    38,    37,    30,
      37,     3,    38,    31,     5,    38,    32,    32,     3,    38,
      29,    33,     3,    29,    31,    38,    31,     3,     3,    30,
      94,    31,    31,    30,    38,    31,   200,    57,   125,   220,
     187,   190,    59,   204,   128,    17,    -1,   212
  };

  const signed char
  VerilogParse::yystos_[] =
  {
       0,    43,    44,     0,    45,    88,     7,    22,    89,     5,
       5,    90,    91,    29,    30,    39,    23,    32,    54,     5,
      31,    33,    34,    46,    47,    48,    50,    51,    52,    81,
      82,    83,    88,     3,     4,     6,    92,    91,     1,     8,
       9,    10,    11,    55,    56,    57,    61,    64,    68,    72,
      88,    36,    29,     5,    49,    50,    31,    32,    31,    32,
      16,    17,    18,    53,    29,    34,    69,    70,    71,    80,
      81,    82,    83,    85,     5,    36,    58,    59,     5,    62,
      63,     5,    12,    13,    14,    15,    16,    17,    18,    19,
      20,    65,     3,    54,    30,    32,    35,    29,    47,    29,
       5,    52,    67,    70,    12,    12,    21,    12,    21,    36,
      67,     4,    81,    82,    83,    84,    85,    86,    87,    29,
      32,    39,    39,     3,    29,    32,    39,    29,    32,     5,
      41,    73,    36,    66,    67,    37,    38,     8,    31,    48,
      50,    54,    54,     3,    32,    35,    70,    87,     3,     4,
       5,     6,    24,    30,    40,    60,    37,    59,     6,    60,
      63,    30,    30,     5,     3,    29,    32,     3,    31,     8,
       8,    37,    87,    60,    60,     5,    24,    25,    26,    27,
       3,    33,    75,    76,    77,    78,    87,    34,    60,    74,
      30,    37,    67,    38,     3,    31,    60,    60,    60,    60,
      38,     5,    31,    32,    32,    74,    31,    32,    75,     3,
      38,    58,    30,    36,    29,    87,    78,    35,    60,    31,
      38,    67,    29,     5,    31,    79,    83,    84,    85,     3,
      29,    66,    31,    36,    31,    37,    38,    29,     3,     3,
      30,    38,    38,    31,    87,    31,    30,    31,    31,    87,
      31
  };

  const signed char
  VerilogParse::yyr1_[] =
  {
       0,    42,    43,    44,    44,    45,    45,    45,    45,    46,
      46,    47,    47,    47,    48,    48,    49,    49,    50,    50,
      50,    51,    51,    51,    52,    52,    53,    53,    53,    53,
      53,    53,    53,    53,    54,    54,    54,    55,    55,    55,
      55,    55,    56,    57,    57,    58,    58,    59,    59,    60,
      60,    60,    60,    60,    60,    60,    60,    60,    60,    61,
      62,    62,    63,    63,    64,    64,    65,    65,    65,    65,
      65,    65,    65,    65,    65,    66,    66,    67,    67,    68,
      69,    69,    70,    71,    71,    72,    72,    73,    74,    74,
      74,    75,    75,    75,    76,    76,    77,    77,    78,    78,
      78,    78,    78,    78,    78,    78,    79,    79,    79,    80,
      80,    80,    81,    82,    83,    84,    85,    86,    86,    87,
      87,    87,    87,    87,    88,    88,    89,    90,    90,    91,
      91,    92,    92,    92
  };

  const signed char
  VerilogParse::yyr2_[] =
  {
       0,     2,     1,     0,     2,     6,     8,     9,     9,     1,
       3,     1,     4,     5,     1,     3,     1,     3,     1,     1,
       1,     1,     3,     3,     3,     8,     1,     2,     1,     2,
       2,     1,     2,     2,     0,     2,     2,     1,     1,     1,
       1,     2,     1,     3,     8,     1,     3,     3,     3,     1,
       2,     1,     1,     2,     3,     3,     3,     3,     3,     3,
       1,     3,     3,     3,     4,     9,     1,     1,     1,     1,
       1,     1,     1,     1,     1,     1,     3,     1,     1,     3,
       1,     3,     3,     1,     1,     7,     8,     4,     1,     3,
       3,     0,     1,     1,     1,     3,     1,     3,     4,     5,
       8,     5,     7,     8,     9,    10,     1,     1,     1,     1,
       1,     1,     1,     4,     6,     1,     3,     1,     3,     1,
       1,     1,     1,     1,     0,     2,     3,     1,     3,     1,
       3,     1,     1,     1
  };


#if YYDEBUG
  // YYTNAME[SYMBOL-NUM] -- String name of the symbol SYMBOL-NUM.
  // First, the terminals, then, starting at \a YYNTOKENS, nonterminals.
  const char*
  const VerilogParse::yytname_[] =
  {
  "\"end of file\"", "error", "\"invalid token\"", "INT", "CONSTANT",
  "ID", "STRING", "MODULE", "ENDMODULE", "ASSIGN", "PARAMETER", "DEFPARAM",
  "WIRE", "WAND", "WOR", "TRI", "INPUT", "OUTPUT", "INOUT", "SUPPLY1",
  "SUPPLY0", "REG", "ATTR_OPEN", "ATTR_CLOSED", "'-'", "'+'", "'*'", "'/'",
  "NEG", "';'", "'('", "')'", "','", "'.'", "'{'", "'}'", "'['", "':'",
  "']'", "'='", "'`'", "'#'", "$accept", "file", "modules", "module",
  "port_list", "port", "port_expr", "port_refs", "port_ref", "port_dcls",
  "port_dcl", "port_dcl_type", "stmts", "stmt", "stmt_seq", "parameter",
  "parameter_dcls", "parameter_dcl", "parameter_expr", "defparam",
  "param_values", "param_value", "declaration", "dcl_type", "dcl_args",
  "dcl_arg", "continuous_assign", "net_assignments", "net_assignment",
  "net_assign_lhs", "instance", "parameter_values", "parameter_exprs",
  "inst_pins", "inst_ordered_pins", "inst_named_pins", "inst_named_pin",
  "named_pin_net_expr", "net_named", "net_scalar", "net_bit_select",
  "net_part_select", "net_constant", "net_expr_concat", "net_exprs",
  "net_expr", "attr_instance_seq", "attr_instance", "attr_specs",
  "attr_spec", "attr_spec_value", YY_NULLPTR
  };
#endif


#if YYDEBUG
  const short
  VerilogParse::yyrline_[] =
  {
       0,   125,   125,   128,   130,   134,   136,   138,   140,   145,
     149,   154,   155,   157,   162,   163,   167,   171,   176,   177,
     178,   182,   186,   190,   199,   201,   206,   207,   208,   209,
     210,   211,   212,   213,   218,   219,   221,   231,   232,   233,
     234,   235,   240,   245,   247,   252,   254,   259,   261,   266,
     268,   270,   272,   273,   275,   277,   279,   281,   283,   288,
     293,   295,   300,   302,   307,   309,   314,   315,   316,   317,
     318,   319,   320,   321,   322,   326,   330,   337,   339,   344,
     349,   353,   358,   363,   364,   368,   370,   375,   379,   380,
     382,   387,   388,   389,   394,   398,   404,   408,   416,   418,
     420,   422,   425,   427,   430,   432,   437,   438,   439,   443,
     444,   445,   449,   454,   459,   464,   469,   474,   478,   483,
     484,   485,   486,   487,   492,   493,   498,   503,   507,   512,
     514,   519,   521,   523
  };

  void
  VerilogParse::yy_stack_print_ () const
  {
    *yycdebug_ << "Stack now";
    for (stack_type::const_iterator
           i = yystack_.begin (),
           i_end = yystack_.end ();
         i != i_end; ++i)
      *yycdebug_ << ' ' << int (i->state);
    *yycdebug_ << '\n';
  }

  void
  VerilogParse::yy_reduce_print_ (int yyrule) const
  {
    int yylno = yyrline_[yyrule];
    int yynrhs = yyr2_[yyrule];
    // Print the symbols being reduced, and their result.
    *yycdebug_ << "Reducing stack by rule " << yyrule - 1
               << " (line " << yylno << "):\n";
    // The symbols being reduced.
    for (int yyi = 0; yyi < yynrhs; yyi++)
      YY_SYMBOL_PRINT ("   $" << yyi + 1 << " =",
                       yystack_[(yynrhs) - (yyi + 1)]);
  }
#endif // YYDEBUG

  VerilogParse::symbol_kind_type
  VerilogParse::yytranslate_ (int t) YY_NOEXCEPT
  {
    // YYTRANSLATE[TOKEN-NUM] -- Symbol number corresponding to
    // TOKEN-NUM as returned by yylex.
    static
    const signed char
    translate_table[] =
    {
       0,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,    41,     2,     2,     2,     2,
      30,    31,    26,    25,    32,    24,    33,    27,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,    37,    29,
       2,    39,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,    36,     2,    38,     2,     2,    40,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,    34,     2,    35,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     2,     2,     2,     2,
       2,     2,     2,     2,     2,     2,     1,     2,     3,     4,
       5,     6,     7,     8,     9,    10,    11,    12,    13,    14,
      15,    16,    17,    18,    19,    20,    21,    22,    23,    28
    };
    // Last valid token kind.
    const int code_max = 279;

    if (t <= 0)
      return symbol_kind::S_YYEOF;
    else if (t <= code_max)
      return static_cast <symbol_kind_type> (translate_table[t]);
    else
      return symbol_kind::S_YYUNDEF;
  }

#line 55 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"
} // sta
#line 2016 "/home/jsliang/GPU-DPO/build/src/sta/VerilogParse.cc"

#line 527 "/home/jsliang/GPU-DPO/src/sta/verilog/VerilogParse.yy"

