use nockvm::interpreter::Context;
use nockvm::jets::util::slot;
use nockvm::jets::JetErr;
use nockvm::noun::{Atom, Noun, D};

use crate::form::shape::{dyck, leaf_sequence};

pub fn leaf_sequence_jet(context: &mut Context, subject: Noun) -> Result<Noun, JetErr> {
    let space = context.stack.noun_space();
    let t = slot(subject, 6, &space)?;
    leaf_sequence(&mut context.stack, t, &space)
}

pub fn dyck_jet(context: &mut Context, subject: Noun) -> Result<Noun, JetErr> {
    let space = context.stack.noun_space();
    let stack = &mut context.stack;
    let t = slot(subject, 6, &space)?;
    dyck(stack, t, &space)
}

pub fn num_of_leaves_jet(context: &mut Context, subject: Noun) -> Result<Noun, JetErr> {
    let space = context.stack.noun_space();
    let tuple = slot(subject, 6, &space)?;

    if tuple.is_atom() {
        return Ok(D(1));
    }

    let tuple = tuple.in_space(&space).as_cell()?;
    let mut num_leaves = 0;
    let mut next = vec![tuple];

    while let Some(curr) = next.pop() {
        let (head, tail) = (curr.head(), curr.tail());
        if head.is_atom() {
            num_leaves += 1;
        } else {
            next.push(head.as_cell()?);
        }

        if tail.is_atom() {
            num_leaves += 1;
        } else {
            next.push(tail.as_cell()?);
        }
    }

    Ok(Atom::new(&mut context.stack, num_leaves as u64).as_noun())
}

#[cfg(test)]
mod tests {
    use nockvm::jets::util::test::*;
    use nockvm::noun::{D, T};

    use super::*;

    #[test]
    fn test_mont_reduction_jet() {
        let c = &mut init_context();

        // > (leaf-sequence:shape.zeke 1)
        // ~[1]
        let sam = D(1);
        let res = T(&mut c.stack, &[D(1), D(0)]);
        assert_jet(c, leaf_sequence_jet, sam, res);

        // > (leaf-sequence:shape.zeke ~)
        // ~[0]
        let sam = D(0);
        let res = T(&mut c.stack, &[D(0), D(0)]);
        assert_jet(c, leaf_sequence_jet, sam, res);

        // > (leaf-sequence:shape.zeke ~[1 2 3])
        // ~[1 2 3 0]
        let sam = T(&mut c.stack, &[D(1), D(2), D(3), D(0)]);
        let res = T(&mut c.stack, &[D(1), D(2), D(3), D(0), D(0)]);
        assert_jet(c, leaf_sequence_jet, sam, res);

        // > (leaf-sequence:shape.zeke [[1 2] 3])
        // ~[1 2 3]
        let t12 = T(&mut c.stack, &[D(1), D(2)]);
        let sam = T(&mut c.stack, &[t12, D(3), D(0)]);
        let res = T(&mut c.stack, &[D(1), D(2), D(3), D(0), D(0)]);
        assert_jet(c, leaf_sequence_jet, sam, res);

        // > (leaf-sequence:shape.zeke [[1 2] 3 [4 5] 6])
        // ~[1 2 3 4 5 6]
        let t12 = T(&mut c.stack, &[D(1), D(2)]);
        let t45 = T(&mut c.stack, &[D(4), D(5)]);
        let sam = T(&mut c.stack, &[t12, D(3), t45, D(6)]);
        let res = T(&mut c.stack, &[D(1), D(2), D(3), D(4), D(5), D(6), D(0)]);
        assert_jet(c, leaf_sequence_jet, sam, res);
    }
}
